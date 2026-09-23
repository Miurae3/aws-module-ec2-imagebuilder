# AWS EC2 Image Builder Terraform Module

Módulo Terraform reutilizável para criação da **fundação de infraestrutura do AWS EC2 Image Builder** utilizada na construção de imagens Linux de containers.

Esta primeira versão cria somente a camada necessária para que etapas posteriores possam utilizar o Image Builder com uma infraestrutura de build controlada, segura e de baixo custo.

O módulo foi desenhado para ser consumido pelo repositório raiz `mmsorg-iac` e não cria VPC, subnet, NAT Gateway, VPC Endpoint ou ECR.

## Escopo desta versão

Esta versão cria:

- IAM Role da instância temporária de build;
- managed policy attachments requeridos para builds de containers;
- IAM Instance Profile;
- Security Group dedicado ao workload;
- regra de saída HTTPS;
- EC2 Image Builder Infrastructure Configuration.

Esta versão **não** cria:

- components;
- container recipes;
- image pipelines;
- distribution configurations;
- ECR repository;
- S3 bucket para logs;
- CloudWatch Log Groups;
- NAT Gateway;
- VPC Endpoints;
- key pair;
- SNS;
- recursos para AMIs;
- recursos Windows.

## Arquitetura

```text
mmsorg-iac
│
├── module "vpc"
│   └── public_subnet_ids["build"]
│
└── module "ec2_image_builder"
    │
    ├── IAM Role
    │   ├── EC2InstanceProfileForImageBuilder
    │   ├── EC2InstanceProfileForImageBuilderECRContainerBuilds
    │   └── AmazonSSMManagedInstanceCore
    │
    ├── IAM Instance Profile
    │
    ├── Security Group
    │   ├── ingress: nenhum
    │   └── egress: TCP/443
    │
    └── Image Builder Infrastructure Configuration
        └── instância EC2 temporária durante o build
```

## Integração com o módulo VPC

O módulo recebe somente um `subnet_id` e descobre internamente a VPC através de `data.aws_subnet.this`.

O contrato entre os módulos ocorre exclusivamente no `mmsorg-iac`:

```hcl
module "vpc" {
  source = "<vpc-module>"

  name            = "image-builder"
  ipv4_cidr_block = "10.10.0.0/16"

  public_subnets = {
    build = {
      ipv4_cidr_block         = "10.10.0.0/24"
      availability_zone       = "sa-east-1a"
      map_public_ip_on_launch = true
    }
  }

  tags = local.common_tags
}

module "ec2_image_builder" {
  source = "<ec2-image-builder-module>"

  name      = "container-image-builder"
  subnet_id = module.vpc.public_subnet_ids["build"]

  tags = local.common_tags
}
```

O módulo de EC2 Image Builder não conhece o módulo de VPC e o módulo de VPC não conhece o Image Builder.

## Conectividade da subnet

As instâncias utilizadas para builds de containers precisam de conectividade de saída para serviços utilizados pelo Image Builder e pelo Systems Manager e, dependendo da receita, para registries externos.

Na arquitetura inicial de menor custo, o cenário esperado é:

```text
Public Subnet
│
├── map_public_ip_on_launch = true
│
├── Route Table
│   └── 0.0.0.0/0 -> Internet Gateway
│
└── EC2 temporária do Image Builder
```

O módulo de VPC mantém `map_public_ip_on_launch = false` por padrão, o que é o comportamento seguro e reutilizável para a rede. Para a subnet dedicada ao baseline econômico do Image Builder sem NAT Gateway, o `mmsorg-iac` deve habilitar explicitamente esse atributo.

O módulo também pode utilizar uma subnet privada no futuro, desde que essa subnet tenha a conectividade necessária através de NAT Gateway, VPC Endpoints ou outra solução adequada. Por isso, o módulo não valida que a subnet recebida seja pública.

## Security Group

O módulo cria um Security Group específico do workload.

### Ingress

Nenhuma regra de entrada é criada.

A instância de build não precisa receber conexões SSH ou tráfego iniciado externamente para executar o fluxo normal do Image Builder.

### Egress

A configuração inicial permite somente:

```text
TCP/443 -> 0.0.0.0/0
```

Essa regra atende ao baseline de comunicação HTTPS com serviços AWS, Systems Manager e registries de containers.

### Limitação conhecida

Algumas receitas ou Dockerfiles podem utilizar repositórios externos via HTTP/80. Esses builds não funcionarão com o baseline atual.

A porta 80 não é habilitada antecipadamente apenas por conveniência. Se surgir uma necessidade real, a interface do módulo poderá ser evoluída de forma explícita.

## IAM

A instância temporária de build utiliza um IAM Instance Profile criado pelo módulo.

A role possui as seguintes AWS managed policies:

```text
EC2InstanceProfileForImageBuilder
EC2InstanceProfileForImageBuilderECRContainerBuilds
AmazonSSMManagedInstanceCore
```

Essas policies são os pré-requisitos documentados pela AWS para o instance profile utilizado em builds de containers.

O módulo não utiliza `AWSImageBuilderFullAccess`.

A policy `EC2InstanceProfileForImageBuilderECRContainerBuilds` é incluída mesmo antes da criação do ECR porque o escopo deste módulo é exclusivamente a construção de imagens de containers. O repositório ECR será definido em uma etapa posterior e não é dependência desta fundação.

Se futuramente houver necessidade de restringir permissões para repositories específicos, o IAM poderá ser refinado quando os ARNs reais desses repositories fizerem parte do contrato da arquitetura.

## Service-linked role

O módulo não cria manualmente o service-linked role do EC2 Image Builder.

Esse recurso possui escopo de conta e é gerenciado pelo próprio serviço quando necessário. Apropriá-lo neste módulo criaria responsabilidade desnecessária e potencial conflito entre consumidores.

## IMDSv2

A Infrastructure Configuration força:

```hcl
http_tokens                 = "required"
http_put_response_hop_limit = 2
```

Isso obriga o uso de IMDSv2 nas instâncias temporárias.

O hop limit `2` é necessário para builds de containers quando tokens IMDS são obrigatórios.

## Falha de build

O módulo utiliza:

```hcl
terminate_instance_on_failure = true
```

Assim, uma instância que falhar durante o build não permanece executando indefinidamente e gerando cobrança.

Para troubleshooting excepcional, essa decisão pode ser revista futuramente, mas não é exposta como variável nesta primeira versão para evitar um default operacionalmente caro.

## Tipo de instância

O baseline inicial é:

```hcl
instance_types = ["t3.micro"]
```

A escolha prioriza baixo custo para a primeira validação.

`t3.micro` não deve ser interpretada como uma garantia de capacidade suficiente para qualquer Dockerfile. Builds que demandem mais memória, CPU ou espaço temporário devem utilizar um tipo maior informado pelo consumidor.

Exemplo:

```hcl
instance_types = ["t3.small"]
```

O dimensionamento deve ser aumentado somente depois de uma necessidade observada no build real.

## Logging

Esta versão não cria bucket S3 para logs.

A Infrastructure Configuration suporta logging em S3, mas introduzir bucket, retenção e permissões adicionais nesta etapa aumentaria responsabilidades e complexidade sem necessidade concreta.

A estratégia de retenção de logs deverá ser revisitada quando pipeline e execução estiverem definidos.

## EBS

O módulo não expõe volume EBS nesta etapa.

Para o fluxo de containers, configurações relacionadas ao armazenamento utilizado pela construção devem ser avaliadas junto da `container recipe`, quando o tamanho real das layers, Dockerfile e workspace estiver conhecido.

## ECR

Nenhum ECR repository é criado ou recebido por esta versão.

A integração será adicionada posteriormente na camada que criar a container recipe.

O contrato esperado será composto pelo `mmsorg-iac`, por exemplo:

```text
module.vpc.public_subnet_ids["build"]
            │
            └──> module.ec2_image_builder

module.ecr.repository_url
            │
            └──> configuração futura da container recipe
```

## Recursos Terraform

| Recurso | Responsabilidade |
|---|---|
| `data.aws_partition.current` | Evita hardcode da partição AWS nos ARNs das managed policies. |
| `data.aws_subnet.this` | Descobre a VPC associada à subnet recebida. |
| `data.aws_iam_policy_document.assume_role` | Define a trust policy da EC2. |
| `aws_iam_role.this` | Role utilizada pela instância de build. |
| `aws_iam_role_policy_attachment.this` | Associa as managed policies necessárias. |
| `aws_iam_instance_profile.this` | Disponibiliza a role para a instância EC2. |
| `aws_security_group.this` | Security Group dedicado ao build. |
| `aws_vpc_security_group_egress_rule.https` | Libera somente saída HTTPS. |
| `aws_imagebuilder_infrastructure_configuration.this` | Define a infraestrutura das futuras execuções do Image Builder. |

## Requisitos

| Requisito | Versão |
|---|---|
| Terraform | `>= 1.3.0` |
| AWS Provider | `>= 6.0.0` |

A região, credenciais, profiles, `assume_role` e demais configurações do provider devem permanecer no root module.

## Inputs

| Nome | Descrição | Tipo | Default | Obrigatório |
|---|---|---|---|---|
| `name` | Nome base dos recursos desta fundação. | `string` | n/a | sim |
| `subnet_id` | Subnet existente onde a EC2 temporária será iniciada. | `string` | n/a | sim |
| `instance_types` | Tipos EC2 permitidos para os builds. | `set(string)` | `["t3.micro"]` | não |
| `tags` | Tags aplicadas aos recursos suportados. | `map(string)` | `{}` | não |

### `name`

O módulo restringe o nome a 59 caracteres e aos caracteres alfanuméricos, `_` e `-`.

A restrição é mais simples que a permitida individualmente por alguns serviços porque o mesmo nome base também é utilizado para compor nomes de recursos IAM, que possuem limites diferentes.

### `tags`

O mapa aceita no máximo 30 entradas porque `resource_tags` da Infrastructure Configuration, usado para propagar tags aos recursos de build, possui esse limite.

## Outputs

| Nome | Descrição |
|---|---|
| `infrastructure_configuration_arn` | ARN da Infrastructure Configuration para uso nas próximas etapas do Image Builder. |

O módulo não expõe IAM Role ARN, Instance Profile, Security Group ID ou VPC ID porque esses valores ainda não fazem parte do contrato necessário para outros módulos.

## Custos

Os recursos persistentes criados nesta fundação — IAM, Security Group e Infrastructure Configuration — não representam o principal custo do fluxo.

Os custos passam a ocorrer principalmente quando um build é executado, por exemplo:

- instância EC2 temporária;
- armazenamento utilizado durante o build;
- IPv4 público enquanto estiver associado;
- tráfego de dados;
- armazenamento posterior no ECR;
- logs, conforme a configuração futura.

A arquitetura evita nesta etapa recursos de custo contínuo como:

- NAT Gateway dedicado;
- Elastic IP dedicado;
- VPC Interface Endpoints;
- S3 bucket exclusivo de logging;
- Dedicated Hosts.

## Próximas etapas

Após validar esta fundação, a evolução natural é:

1. definir os components necessários ao build Linux;
2. definir a container recipe;
3. definir o contrato com o ECR quando o repository existir;
4. dimensionar EBS de acordo com o build real;
5. criar o image pipeline;
6. definir logging e retenção;
7. adicionar execução manual ou agendada somente quando necessário;
8. avaliar refinamentos de IAM com os ARNs reais dos recursos consumidores.

Essas funcionalidades não fazem parte desta versão.
