# Atividade Docker

Este Repositório é uma API HTTP minima de mural de recados, usada como projeto/atividade
da trilha de Docker da CJR. O objetivo e aprender a infraestrutura em volta: o
codigo da API vem pronto e voce escreve o Dockerfile e o compose ao longo das
sessoes.

## Pre-requisitos

- Docker instalado e rodando
- git
- um terminal

## Como usar

Clone o repositorio e trabalhe sempre na raiz. A cada sessao voce cria ou ajusta
um arquivo de infraestrutura (Dockerfile, .dockerignore, compose.yaml) e valida
com o verificar.sh. O codigo em api/ e db/ nao precisa ser alterado.

## Sessoes

| Sessao | Entrega |
|--------|---------|
| 1 | Subir um Postgres em container aceitando conexao na porta esperada |
| 2 | Container do banco chamado docker-db, acessivel por exec e logs |
| 3 | Puxar e rodar a imagem ghcr.io/<org>/docker |
| 4 | Escrever o Dockerfile da API na raiz; imagem builda e /health responde |
| 5 | Dockerfile multi-stage abaixo de 200MB e .dockerignore com node_modules |
| 6 | Volume nomeado para o banco e rede definida pelo usuario |
| 7 | compose.yaml sobe API e banco; variaveis vem do .env |
| 8 | Imagem publicada e compose funcionando com a tag remota |

## Verificacao

Rode as checagens da sessao atual:

    ./verificar.sh <numero-da-sessao>

O numero vai de 1 a 8. Cada checagem imprime OK ou FALHA com uma linha do que
fazer. O script sai com codigo 0 se tudo passou e 1 caso contrario.

## Entrega

Abra um pull request com sua entrega final. O workflow builda seu Dockerfile,
sobe o compose e falha se /health nao responder.

## Gabarito

A pasta gabarito/ tem versoes de referencia do Dockerfile e do compose. Consulte
so depois de tentar por conta propria.
