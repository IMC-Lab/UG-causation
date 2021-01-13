#!/usr/bin/Rscript
##
## Simulate data for UG with causal judgments
##
library(ggplot2)
library(tidyr)
library(dplyr)
library(lme4)
library(lmerTest)
library(ggeffects)

cat('\nSetting up priors...')
## prior definitions for AI players
N <- 10
priors.ai <- data.frame(player=c('A', 'B', 'C'),
                        rate=c(0.8, 0.5, 0.2)) %>%
    mutate(offer.s1=rate*N,
           offer.s2=(1-rate)*N,
           accept.s1=(1-rate)*N,
           accept.s2=rate*N)

## Display densities of AI priors for proposing/accepting offers
priors.ai %>% crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(poffer=dbeta(offer, offer.s1, offer.s2)) %>%
    ggplot(aes(x=offer, y=poffer, color=player)) +
    geom_line() + theme_classic() + ylab('P(offer=X | player)') +
    ggtitle('When AI proposes, P(offer=X | player)')
ggsave('ai-proposal-prior.png')

priors.ai %>% crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(paccept=pbeta(offer, accept.s1, accept.s2)) %>%
    ggplot(aes(x=offer, y=paccept, color=player)) +
    geom_line() + theme_classic() +
    ylab('P(Accept | offer=X, player)') +
    ggtitle('When AI accepts, P(Accept | offer=X, player)')
ggsave('ai-acceptance-prior.png')

priors.ai %>% crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(cause=(1 - dbeta(offer, offer.s1, offer.s2) / 10)) %>%
    ggplot(aes(x=offer, y=cause, color=player)) + ylim(0, 1) +
    geom_line() + theme_classic() + ylab('Approx. Causal Judgment')
ggsave('cause-accept.png')

priors.ai %>% crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(cause=(1 - pbeta(offer, accept.s1, accept.s2)/2)) %>%
    ggplot(aes(x=offer, y=cause, color=player)) +
    geom_line() + theme_classic() + ylim(0, 1) +
    ylab('Approx. Causal Judgment | AI rejected offer')
ggsave('cause-propose-accept.png')

priors.ai %>% crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(cause=(1 + pbeta(offer, accept.s1, accept.s2))/2) %>%
    ggplot(aes(x=offer, y=cause, color=player)) +
    geom_line() + theme_classic() + ylim(0, 1) +
    ylab('Approx. Causal Judgment | AI accepted offer')
ggsave('cause-propose-reject.png')


## Define subject-level priors for acceptance
##
## Here we're assuming that subjects are approximately fair, with
##   priors ~ B(s1, s2), s1 ~ N(10, 2), s2 ~ N(10, 2).
##
## We're also assuming that subjects behave identically with different partners
##
## These can be changed in the future to better match human behavior
N <- 100  # number of participants
priors.subj <- data.frame(id=1:N,
                          condition=rep(c('propose', 'accept'), each=N/2),
                          subj.s1=rnorm(N, mean=10, sd=3),
                          subj.s2=rnorm(N, mean=10, sd=3))

## Display subject priors
png('human-proposal-prior.png')
priors.subj %>% filter(condition == 'propose') %>%
    crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(poffer=dbeta(offer, subj.s1, subj.s2)) %>%
    ggplot(aes(x=offer, y=poffer)) +
    stat_smooth(method="loess", span=0.1, se=TRUE, alpha=0.3) + theme_classic() +
    ylab('P(offer=X | player)') +
    ggtitle('When Participant proposes, P(offer=X)')
dev.off()
png('human-acceptance-prior.png')
priors.subj %>% filter(condition == 'accept') %>%
    crossing(offer=seq(from=0, to=1, by=0.01)) %>%
    mutate(paccept=pbeta(offer, subj.s1, subj.s2)) %>%
    ggplot(aes(x=offer, y=paccept)) + 
    stat_smooth(method="loess", span=0.1, se=TRUE, alpha=0.3) + theme_classic() +
    ylab('P(Accept | offer=X, player)') +
    ggtitle('When Participant accepts, P(Accept | offer=X)')
dev.off()


cat('done.\n')

## Simulate trial-level data
##
cat('Simulating data...')
TRIALS <- 25 # number of trials per subj/AI
df <- priors.subj %>% crossing(priors.ai) %>%
    mutate(ai.s1=ifelse(condition == 'propose', accept.s1, offer.s1),
           ai.s2=ifelse(condition == 'propose', accept.s2, offer.s2)) %>%
    select(-offer.s1, -offer.s2, -accept.s1, -accept.s2) %>%
    crossing(trial=1:TRIALS) %>%
    rowwise %>%
    mutate(offer=ifelse(condition=='propose',
                        rbeta(1, subj.s1, subj.s2),
                        rbeta(1, ai.s1, ai.s2)),
           accept=ifelse(condition=='propose',
                         rbinom(1, 1, pbeta(offer, ai.s1, ai.s2)),
                         rbinom(1, 1, pbeta(offer, subj.s1, subj.s2))),
           earning=ifelse(accept, offer, 0),
           cause=(1 - dbeta(offer)/10))
cat('done.\n')


cat('Fitting lmer...')
m <- glmer(accept ~ player * offer * condition + (1 | id),
           family=binomial(link='logit'),
           data=df)
summary(m)
png('lmer.png')
m %>% ggpredict(terms=c('offer [all]', 'player', 'condition')) %>% plot()
dev.off()
cat('done.')
