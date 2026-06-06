#!/usr/bin/env Rscript
# 08_text_drivers.R — Text-as-data extension of the drivers-of-magnitude model.
# Does the campaign's TITLE + BLURB text predict how much a funded project raises,
# beyond the structured features? Two questions:
#   (1) WHICH words/phrases associate with raising more (interpretable LASSO);
#   (2) Does adding text IMPROVE honest out-of-sample R^2 over structured features?
#
# Method: bag-of-words (stemmed unigrams + bigrams) -> sparse doc-term matrix ->
# LASSO (glmnet). (No topic-model/embedding packages installed; TF-IDF+LASSO is the
# interpretable, dependency-light choice.)
#
# *** Referee Minor (leakage) FIX: vocabulary selection (document-frequency >= 10)
# is now performed INSIDE each CV training fold, so test-fold tokens never inform
# the feature set. The interpretive coefficient figure (question 1) still uses the
# full-corpus vocabulary, which is fine because it is description, not a CV estimate.
#
# Sample: funded core ttrpg BOOKS only (class_accessory == 0), 2015+. Restricting to
# books keeps the text interpretation coherent: in the pooled book+accessory sample,
# physical-product words (diorama/scenery/minis) mostly flag the accessory CLASS
# rather than a wording effect, so we drop accessories here.
# Associational; blurb wording is itself a choice correlated with project quality.
#
# Out: tables/text_*.csv, figures/text_top_terms.png

suppressPackageStartupMessages({
  library(tidyverse); library(tidytext); library(SnowballC)
  library(Matrix); library(glmnet)
})
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

feat <- read_csv(file.path(proj, "data", "processed", "ttrpg_model_features.csv.gz"),
                 show_col_types = FALSE) %>%
  filter(class_accessory == 0) %>%             # BOOKS ONLY (see header)
  mutate(launch_year = factor(launch_year), launch_month = factor(launch_month),
         launch_dow = factor(launch_dow))
txt <- read_csv(file.path(proj, "data", "processed", "tabletop_classified.csv.gz"),
                show_col_types = FALSE) %>%
  select(id, name, blurb) %>% filter(id %in% feat$id) %>%
  mutate(text = str_to_lower(paste(coalesce(name, ""), coalesce(blurb, ""))))

# ---- raw token long-table (id, term, n): unigrams + bigrams, NO global filter ----
uni <- txt %>%
  unnest_tokens(word, text) %>% anti_join(stop_words, by = "word") %>%
  filter(str_detect(word, "^[a-z]+$"), nchar(word) >= 3) %>%
  mutate(term = wordStem(word)) %>% count(id, term)
bi <- txt %>%
  unnest_tokens(bg, text, token = "ngrams", n = 2) %>% filter(!is.na(bg)) %>%
  separate(bg, c("w1", "w2"), sep = " ", remove = FALSE) %>%
  filter(!w1 %in% stop_words$word, !w2 %in% stop_words$word,
         str_detect(w1, "^[a-z]+$"), str_detect(w2, "^[a-z]+$")) %>%
  transmute(id, term = paste(w1, w2)) %>% count(id, term)
tokens <- bind_rows(uni, bi)
ndoc <- nrow(txt)

# canonical order; structured design matrix; outcome
ord <- feat$id
y <- setNames(feat$log10_pledged, feat$id)[as.character(ord)]
xvars <- c("log10_goal", "duration_days", "has_video", "staff_pick",
           "blurb_words", "title_words", "country_us",   # class_accessory dropped (books only)
           "creator_prior_funded", "creator_is_repeat",
           "is_dnd5e", "is_osr", "is_pbta", "is_zine")
Xs_full <- sparse.model.matrix(as.formula(paste("~", paste(c(xvars, "launch_year",
            "launch_month", "launch_dow"), collapse = " + "))), data = feat)[, -1]
rownames(Xs_full) <- feat$id

make_dtm <- function(ids, vocab) {           # rows=ids (order), cols=vocab (order)
  sub <- tokens %>% filter(id %in% ids, term %in% vocab)
  Matrix::sparseMatrix(i = match(sub$id, ids), j = match(sub$term, vocab),
                       x = sub$n, dims = c(length(ids), length(vocab)),
                       dimnames = list(as.character(ids), vocab))
}

# ---- (2) honest 5-fold CV with PER-FOLD vocabulary selection ----------------
folds <- sample(rep(1:5, length.out = length(ord)))
r2 <- function(o, p) 1 - sum((o - p)^2) / sum((o - mean(o))^2)
ps <- pt <- pc <- numeric(length(ord))
for (k in 1:5) {
  tr <- which(folds != k); te <- which(folds == k)
  tr_ids <- ord[tr]; te_ids <- ord[te]
  # vocabulary chosen ONLY from training documents
  vocab_k <- tokens %>% filter(id %in% tr_ids) %>% distinct(id, term) %>%
    count(term, name = "df") %>% filter(df >= 10, df <= 0.5 * length(tr_ids)) %>% pull(term)
  Xt_tr <- make_dtm(tr_ids, vocab_k); Xt_te <- make_dtm(te_ids, vocab_k)
  Xs_tr <- Xs_full[as.character(tr_ids), ]; Xs_te <- Xs_full[as.character(te_ids), ]
  ytr <- y[tr]
  g0 <- cv.glmnet(Xs_tr, ytr, alpha = 1); ps[te] <- as.numeric(predict(g0, Xs_te, s = "lambda.min"))
  g1 <- cv.glmnet(Xt_tr, ytr, alpha = 1); pt[te] <- as.numeric(predict(g1, Xt_te, s = "lambda.min"))
  g2 <- cv.glmnet(cbind(Xs_tr, Xt_tr), ytr, alpha = 1)
  pc[te] <- as.numeric(predict(g2, cbind(Xs_te, Xt_te), s = "lambda.min"))
}
cmp <- tibble(features = c("structured only", "text only", "structured + text"),
              cv_r2 = c(r2(y, ps), r2(y, pt), r2(y, pc)),
              note = "vocabulary selected within each training fold (no leakage)")
write_csv(cmp, file.path(tabd, "text_cv_r2_comparison.csv"))

# ---- (1) interpretable LASSO on full corpus (description, not CV) ------------
docfreq <- tokens %>% distinct(id, term) %>% count(term, name = "df")
keep <- docfreq %>% filter(df >= 10, df <= 0.5 * ndoc) %>% pull(term)
Xt_full <- make_dtm(ord, keep)
Xc_full <- cbind(Xs_full[as.character(ord), ], Xt_full)
cat(sprintf("full-corpus vocab (interpretation): %d terms\n", length(keep)))
cvc <- cv.glmnet(Xc_full, y, alpha = 1)
co <- as.matrix(coef(cvc, s = "lambda.min"))
coef_tbl <- tibble(term = rownames(co), coef = co[, 1]) %>%
  filter(term %in% colnames(Xt_full), coef != 0) %>% arrange(desc(coef))
write_csv(coef_tbl, file.path(tabd, "text_lasso_terms.csv"))

top <- bind_rows(slice_max(coef_tbl, coef, n = 15), slice_min(coef_tbl, coef, n = 15)) %>%
  mutate(dir = if_else(coef > 0, "raises more", "raises less"), term = fct_reorder(term, coef))
p <- ggplot(top, aes(coef, term, fill = dir)) + geom_col() +
  scale_fill_manual(values = c("raises more" = "#2c7fb8", "raises less" = "#d7191c"), name = NULL) +
  labs(title = "Title/blurb terms predicting pledged $ for funded RPG books (LASSO)",
       subtitle = "coefficient on log10 pledged, controlling for structured features; several strong terms are brand names or tokenization artifacts (see write-up)",
       x = "LASSO coefficient (log10 pledged)", y = NULL)
ggsave(file.path(figd, "text_top_terms.png"), p, width = 10, height = 7, dpi = 130)

cat("\n=== Honest 5-fold CV R^2 (per-fold vocabulary; leakage-free) ===\n")
print(as.data.frame(cmp %>% select(features, cv_r2) %>% mutate(cv_r2 = round(cv_r2, 3))))
cat(sprintf("\nnonzero text terms (interpretation): %d\n", nrow(coef_tbl)))
cat("\n=== Top 12 terms RAISING / LOWERING pledged ===\n")
print(as.data.frame(slice_max(coef_tbl, coef, n = 12) %>% mutate(coef = round(coef, 3))))
print(as.data.frame(slice_min(coef_tbl, coef, n = 12) %>% mutate(coef = round(coef, 3))))
cat("\nFigures -> figures/text_top_terms.png ; tables -> tables/text_*.csv\n")
