<div align="center">

# Setup RavenDB — GitHub Action

[🇺🇸 English](README.md) · **🇧🇷 Português (Brasil)**

Uma GitHub Action gratuita e de código aberto que sobe um servidor **RavenDB** real
no seu pipeline de CI — via imagem Docker oficial, pronta em segundos, sem
configuração manual.

[![Self-test](https://img.shields.io/github/actions/workflow/status/leadsoftlucas/ravendb-github-action/test.yml?branch=main&label=self-test)](.github/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![RavenDB](https://img.shields.io/badge/RavenDB-CI-b3131e)](https://ravendb.net)
[![Docker: ravendb/ravendb](https://img.shields.io/badge/Docker-ravendb%2Fravendb-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/ravendb/ravendb)

</div>

Ela existe para que um workflow possa rodar testes de integração contra uma instância
real do [RavenDB](https://ravendb.net) — não um mock, não um stub embarcado — sem
instalação manual e sem depender de um serviço externo. O servidor fica pronto em
segundos. Nos runners hospedados pelo GitHub, ele desaparece junto com o runner ao fim do
job; a action não tem um passo de limpeza próprio (veja [Notas de segurança](#notas-de-segurança)).

> **Projeto independente, não é um lançamento oficial da RavenDB.** Esta action é
> construída e mantida por [Lucas R. Tavares](https://github.com/leadsoftlucas),
> funcionário da RavenDB, por iniciativa própria e na sua conta pessoal do GitHub.
> Ela **não é publicada pela empresa RavenDB, não tem cobertura do suporte oficial
> da RavenDB, e não está listada no GitHub Marketplace.** Use, faça fork, ou copie
> partes dela — só não assuma que ela carrega o respaldo institucional da RavenDB.
> Veja [Status e escopo](#status-e-escopo) abaixo.

## O que ela faz

- Baixa a imagem Docker oficial `ravendb/ravendb` e sobe um container configurado
  para inicialização automática e sem segurança (sem HTTPS, sem certificado de
  cliente) — a forma correta e documentada de subir um banco de CI de vida curta,
  nunca algo acessível de fora do runner.
- Consulta repetidamente o próprio endpoint `/setup/alive` do RavenDB até o servidor
  responder, para que os passos seguintes do workflow nunca corram o risco de bater
  num servidor que ainda não está pronto.
- Opcionalmente cria um banco de dados nomeado e, opcionalmente, carrega o conjunto
  de dados de exemplo **Northwind**, já embutido no RavenDB — útil para um exemplo
  autocontido ou um smoke test que precisa de dados reais sem versionar fixtures.
- Expõe a `url` do servidor e o `container-id` do container como outputs do passo,
  para uso nos passos seguintes.

## O que ela deliberadamente não faz

Esta é a versão gratuita e autocontida de uma action de "RavenDB em CI". Ela não
provisiona nada contra o RavenDB Cloud, não lida com cobrança/billing, e não
configura certificados de cliente ou mTLS para um cluster seguro — isso é um projeto
diferente e mais pesado. Se você precisa de um RavenDB de produção, seguro,
multi-node e acessível de fora de um runner de CI, não é isto.

## Início rápido

```yaml
- name: Start RavenDB
  id: ravendb
  uses: leadsoftlucas/ravendb-github-action@main # em uso real, fixe num commit SHA — veja "Versionamento"
  with:
    database-name: MyTestDb

- name: Run integration tests
  run: dotnet test
  env:
    RAVENDB_URL: ${{ steps.ravendb.outputs.url }}
```

## Exemplo completo: consultando os dados de exemplo do Northwind

Este é baseado no workflow que este repositório executa a cada push para verificar que
a action continua funcionando (ele usa `uses: ./` e um passo extra de verificação) — veja [`.github/workflows/test.yml`](.github/workflows/test.yml).

<details>
<summary>YAML completo do workflow</summary>

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Start RavenDB
        id: ravendb
        uses: leadsoftlucas/ravendb-github-action@main
        with:
          database-name: Northwind
          load-sample-data: "true"

      - name: Query Northwind data
        run: |
          curl --fail -X POST \
            "${{ steps.ravendb.outputs.url }}/databases/Northwind/queries" \
            --header "Content-Type: application/json" \
            --data '{"Query": "from Orders"}'
```

</details>

## Inputs

| Nome                        | Descrição                                                                                                                                       | Padrão            |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------ |
| `version`                  | Tag da imagem oficial `ravendb/ravendb` a executar — ex.: `ubuntu-latest`, `ubuntu-latest-lts`, ou uma versão fixa. [Todas as tags](https://hub.docker.com/r/ravendb/ravendb/tags). | `ubuntu-latest`   |
| `port`                     | Porta do host onde a API HTTP do RavenDB é publicada.                                                                                             | `8080`            |
| `container-name`           | Nome dado ao container Docker do RavenDB.                                                                                                         | `ravendb-ci`      |
| `database-name`            | Nome de um banco de dados a ser criado assim que o servidor estiver pronto. Deixe vazio para subir um servidor sem banco.                         | *(vazio)*         |
| `load-sample-data`         | Quando `true` (e `database-name` estiver definido), carrega o conjunto de dados de exemplo Northwind, já embutido no RavenDB.                     | `false`           |
| `startup-timeout-seconds`  | Quantos segundos esperar o RavenDB ficar pronto antes de falhar o passo.                                                                          | `60`              |

## Outputs

| Nome            | Descrição                                                       |
| ---------------- | ------------------------------------------------------------------ |
| `url`           | URL base do servidor RavenDB em execução, ex.: `http://localhost:8080`. |
| `container-id`  | ID do container Docker do servidor RavenDB em execução.            |

## Requisitos

- Um runner Linux com Docker disponível (`ubuntu-latest` nos runners hospedados pelo
  GitHub). O Docker já vem pré-instalado ali; esta action não roda Docker-in-Docker
  nem precisa de qualquer configuração privilegiada.
- Nenhuma licença paga do RavenDB é necessária. O servidor roda sob a licença Community
  gratuita do RavenDB (a action aceita o EULA por você via `RAVEN_License_Eula_Accepted=true`,
  então ao usá-la você concorda com os termos da RavenDB). Valem os limites da edição Community.

## Como funciona

Esta action é implementada como uma **composite action** (YAML puro + um script
shell, sem JavaScript compilado, sem uma Docker container action separada) que
executa `docker run` diretamente no daemon Docker que já existe no próprio runner.
Essa escolha, em vez dos ["service containers"](https://docs.github.com/en/actions/using-containerized-services/about-service-containers)
nativos do GitHub ou de uma Docker container action, segue o mesmo padrão usado por
actions `setup-<database>` comparáveis no ecossistema: mantém as opções do
`docker run` totalmente controladas pelos inputs desta própria action, já
documentados, em vez de duplicar flags de `--health-cmd` específicas do RavenDB em
cada workflow que a consome — e evita Docker-in-Docker por completo, já que os
runners Linux do GitHub já têm um daemon Docker disponível.

A inicialização segue o próprio padrão documentado da RavenDB para configuração
não interativa: `RAVEN_Setup_Mode=None` pula o assistente de configuração
interativo, e `RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork` permite que o
servidor, agora sem segurança, aceite conexões — ambas são variáveis de ambiente que
a [própria documentação Docker da RavenDB](https://docs.ravendb.net/start/containers/dockerfile/dockerfile-overview)
define para exatamente este caso de uso, não um contorno inventado para esta action.
A prontidão é confirmada consultando repetidamente o próprio endpoint `/setup/alive`
do servidor, e o provisionamento opcional de banco/dados de exemplo usa a API REST
documentada da RavenDB (`PUT /admin/databases`, `POST /databases/<nome>/studio/sample-data`)
— as mesmas chamadas que o próprio RavenDB Studio faz.

## Notas de segurança

- O servidor iniciado por esta action é **inseguro por design** —
  sem HTTPS, sem autenticação por certificado de cliente — porque essa é a forma
  correta e documentada de rodar o RavenDB para desenvolvimento local e CI de vida
  curta, onde a instância nunca sobrevive além do job e nunca é acessível de fora
  do runner.
- Nunca publique a porta usada por esta action além do runner, e nunca aponte para
  dados que você não pode se dar ao luxo de expor. Esta action é só para bancos de
  CI efêmeros.
- O container não é removido pela action. Os runners hospedados pelo GitHub são descartados
  após cada job, então nada sobra ali; em runners **self-hosted**, adicione seu próprio passo
  `docker rm -f ravendb-ci` (ex.: `if: always()`), senão o nome de container e a porta fixos
  vão colidir na próxima execução.

## Versionamento

Este repositório ainda não tem uma release marcada com tag. Quando tiver, as
releases seguirão versionamento semântico (`v1`, `v1.2.0`, …) e uma tag de versão
principal móvel (`v1`) vai acompanhar a última release compatível — a mesma
convenção usada pela maioria das GitHub Actions. Até a primeira tag existir, fixe
num commit SHA em vez de `@main` se precisar de uma build que não mude embaixo de
você.

## Status e escopo

Este repositório é um esforço independente para fechar uma lacuna específica e
observável: no momento em que isto foi escrito, buscar por "ravendb"
no [GitHub Marketplace](https://github.com/marketplace) retornava zero resultados,
enquanto bancos comparáveis (MongoDB, DynamoDB, InfluxDB, Couchbase) aparecem
representados por várias actions listadas. Esta é a correção gratuita e de baixo
esforço — uma action no estilo `setup-<database>` para CI, sem cobrança e sem
provisionamento em nuvem. O provisionamento no RavenDB Cloud está fora do escopo deste repositório.

Se a RavenDB (a empresa) decidir adotar, fazer fork, ou assumir oficialmente este
projeto, essa é uma decisão da RavenDB a ser tomada — este repositório não presume
isso de antemão.

## Contribuindo

Issues e pull requests são bem-vindos. Esta é uma action pequena e focada — por
favor, mantenha as mudanças alinhadas com o que está descrito acima, em vez de
expandir o escopo.

## Licença

[MIT](LICENSE) © 2026 Lucas R. Tavares

## Links relacionados

- [Documentação da RavenDB](https://docs.ravendb.net)
- [Imagem Docker da RavenDB no Docker Hub](https://hub.docker.com/r/ravendb/ravendb)
- [Documentação de containers/Docker da RavenDB](https://docs.ravendb.net/start/containers/general-guide)
- [Referência de sintaxe de metadados do GitHub Actions](https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions)
