# Aponta P3 Equipe Online v2.13.0

Aplicativo web compartilhado para apontamento de horas. Toda a equipe utiliza o mesmo banco de dados online.

## O que esta versão possui

- Fluxo Projeto → Área → Sala → Módulo para Montagem Estrutural.
- Cadastros divididos em três subabas.
- Login individual por e-mail e senha.
- Primeiro usuário como Administrador.
- Perfis Administrador, Gestor e Colaborador.
- Apontamento por data, projeto, atividade e horas.
- Histórico e edição conforme permissões.
- Férias e afastamentos individuais por colaborador, com edição, filtros, situação e exclusão.
- Fechamento mensal com envio, aprovação e devolução.
- Projetos, atividades e feriados, com exclusão segura de cadastros sem uso.
- Relatórios e exportação CSV.
- PWA instalável pelo navegador.
- Banco central Supabase com Row Level Security.
- Bloqueio de apontamentos durante férias e afastamentos.
- Exclusão segura de apontamentos e de colaboradores cadastrados por engano.

## Não precisa instalar no notebook

A configuração é feita no navegador. Não é necessário XAMPP, WAMP, PHP, Node.js ou senha de administrador do Windows.

## Instalação

### 1. Criar o banco

1. Crie uma conta em https://supabase.com
2. Crie um projeto.
3. No menu do projeto, abra `SQL Editor`.
4. Clique em `New query`.
5. Abra `schema.sql`, copie todo o conteúdo e execute.
6. Em `Authentication > Providers > Email`, mantenha Email habilitado.
7. Para facilitar os testes, você pode desativar temporariamente `Confirm email`. Em produção, recomenda-se manter a confirmação.
8. Em `Authentication > URL Configuration`, informe a URL pública do aplicativo depois da publicação.

### 2. Configurar o aplicativo

1. No Supabase, abra `Project Settings > API`.
2. Copie:
   - Project URL
   - Publishable key ou anon public key
3. Abra `configurador.html`.
4. Cole os dois dados.
5. Clique em `Gerar config.js`.
6. Substitua o `config.js` da pasta pelo arquivo baixado.

Nunca coloque a `service_role key` no aplicativo.

### 3. Publicar por link

1. Acesse o Netlify Drop no navegador.
2. Arraste a pasta completa `Aponta_P3_Equipe_Online_v2`.
3. Aguarde a criação do link.
4. Copie o link gerado.
5. Volte ao Supabase e configure esse link em:
   - Authentication > URL Configuration > Site URL
   - Redirect URLs
6. Publique novamente se tiver alterado arquivos.

## Primeiro acesso

1. Abra o link publicado.
2. Clique em `Criar conta`.
3. Cadastre o primeiro usuário.
4. O primeiro usuário será automaticamente Administrador.
5. Os demais usuários podem criar a própria conta e entram como Colaborador.
6. O Administrador pode alterar usuários para Gestor na tela Equipe.

## Segurança

A chave pública do Supabase pode ficar no navegador. A proteção dos dados é feita pelas regras RLS do banco. O arquivo `schema.sql` já cria as regras para:

- Colaborador consultar e editar os próprios apontamentos.
- Gestor consultar e revisar toda a equipe.
- Administrador alterar perfis.
- Apenas gestor/administrador manter projetos, atividades e feriados.

## Arquivos

- `index.html`: aplicativo.
- `style.css`: aparência.
- `app.js`: funcionamento.
- `config.js`: dados públicos do Supabase.
- `configurador.html`: gera o config.js.
- `schema.sql`: cria banco, funções e segurança.
- `manifest.webmanifest` e `sw.js`: instalação como PWA.


## Atualização v2.1

Esta versão corrige o retorno da confirmação de e-mail e adiciona:

- Troca explícita do código PKCE por sessão.
- Mensagem de erro quando o link expirou ou a URL não está autorizada.
- Botão para reenviar o e-mail de confirmação.
- Edição de projetos.
- Edição de atividades.
- Edição de feriados.
- Tela Meu perfil para alterar nome e jornada.

### Para quem já executou o schema.sql da versão 2.0

Execute também o arquivo:

`ATUALIZAR_BANCO_v2.1.sql`

Depois publique novamente a pasta, mantendo o seu `config.js` já configurado.

### URL de autenticação

Em Supabase → Authentication → URL Configuration:

- Site URL: use o endereço exato do Netlify.
- Redirect URLs: adicione o mesmo endereço exato e também a variação terminada em `/**`.

Exemplo:

- `https://seu-aplicativo.netlify.app/`
- `https://seu-aplicativo.netlify.app/**`


## Atualização v2.2 — aviso de jornada excedida

- Mostra, enquanto as horas são digitadas:
  - horas já apontadas;
  - horas do novo lançamento;
  - total previsto;
  - horas restantes ou excedentes.
- Destaca o resumo em vermelho quando a jornada será ultrapassada.
- Ao salvar acima da jornada diária, pede confirmação antes de gravar.
- O lançamento continua permitido após a confirmação.
- Não exige atualização no banco de dados.

Para atualizar um site existente, mantenha o seu `config.js`, substitua os arquivos
`app.js`, `style.css`, `index.html` e `sw.js`, e faça um novo deploy no Netlify.


## Atualização v2.3 — e-mail ao enviar para aprovação

Ao clicar em **Enviar para aprovação**, o aplicativo:

1. Fecha o período no banco.
2. Marca os apontamentos como enviados.
3. Chama a Edge Function `enviar-aprovacao`.
4. Envia e-mail aos administradores e gestores ativos.
5. Mostra quantos aprovadores receberam a mensagem.

O e-mail inclui colaborador, período, total de horas, remetente do fechamento
e um botão para abrir o aplicativo.

A falha do e-mail não desfaz o fechamento. Nesse caso, o sistema informa que
o período foi enviado, mas que a notificação não pôde ser entregue.

Consulte `CONFIGURAR_EMAIL_APROVACAO.txt`.


## Atualização v2.4 — Identidade Visual Modular

Esta versão aplica a identidade visual da Modular Data Centers:

- nome visual: Modular | Apontamento de Horas;
- cores principais #052630 e #78AD3E;
- logomarca e ícone da Modular;
- tela Apresentação com objetivos, fluxo e recursos;
- arquivo PowerPoint em `docs/Apresentacao_Apontamento_Horas_Modular.pptx`;
- cache do PWA atualizado para forçar o carregamento da nova identidade.

Para atualizar um site existente, mantenha o seu `config.js`, substitua os arquivos da pasta pelo pacote v2.4 e faça novo deploy no Netlify.


## Atualização v2.5 — bloqueio de apontamentos futuros

Esta versão impede apontamentos em datas posteriores ao dia atual:

- o calendário não permite selecionar datas futuras;
- a criação de apontamento valida novamente antes de salvar;
- a edição também bloqueia datas futuras;
- o botão “Copiar último dia” não copia para data futura;
- o banco Supabase possui um gatilho que recusa INSERT ou UPDATE futuro.

Para atualizar o banco, execute:

`ATUALIZAR_BANCO_v2.5_BLOQUEAR_DATA_FUTURA.sql`

Depois publique novamente os arquivos do aplicativo no Netlify e pressione
`Ctrl + F5`.


## Atualização v2.6 — importar a planilha Apontamento_P3.xlsx

A tela **Importar Excel**, disponível para Administradores, reconhece:

- abas de colaboradores;
- projetos;
- atividades;
- frequência;
- responsável e backup;
- horas numéricas;
- feriados;
- férias.

Regras:

- cada aba deve ser relacionada a um usuário já cadastrado;
- `FDS`, sábado e domingo são ignorados;
- apontamentos futuros são ignorados;
- registros já existentes na mesma data, projeto e atividade são pulados;
- a aba `Total` não é importada;
- a aba `Atividades` alimenta o cadastro de atividades;
- os lançamentos entram como `Rascunho`.

Antes de usar a importação, execute no Supabase:

`ATUALIZAR_BANCO_v2.6_IMPORTAR_EXCEL.sql`


## Atualização v2.7 — backup automático e restauração

- Backup manual pelo aplicativo.
- Restauração JSON exclusiva para Administradores.
- Edge Function segura para exportar e restaurar dados.
- Agente Windows para backup diário em:

`Y:\PLANTA 3\GESTÃO (APONTAMENTOS, HORAS...)\Apontamento Horas\2026`

- Fallback local quando a unidade Y: estiver indisponível.
- Tarefa diária criada no usuário atual, sem solicitar senha de administrador.
- Restauração em modo de mesclagem.

Consulte `CONFIGURAR_BACKUP_AUTOMATICO.txt`.


## Atualização da versão 2.7 para 2.8

1. Faça backup da versão atual.
2. Execute `ATUALIZAR_BANCO_v2.8_FERIAS_AFASTAMENTOS_EXCLUSOES.sql` no Supabase.
3. Publique a Edge Function `excluir-cadastro` usando `FUNCAO_EXCLUIR_CADASTRO.ts`.
4. Publique esta pasta completa no mesmo site do Netlify.
5. Pressione `Ctrl + F5` no primeiro acesso.

Leia `INSTRUCOES_ATUALIZACAO_v2.8.txt` antes de publicar.

## Backup automático v2.8.1

O ZIP agora inclui a pasta `AGENTE_BACKUP_AUTOMATICO`. Execute `Configurar_Backup_Diario.bat` no computador que deverá salvar o backup diariamente. O agente recupera execuções perdidas no próximo login e usa uma pasta de pendentes quando a unidade de rede estiver indisponível.


## Relatórios de equipe — v2.9

Na aba **Relatórios**, escolha:

- **Projetos e horas** para consultar o relatório tradicional de apontamentos;
- **Equipe: horas, férias e afastamentos** para comparar horas trabalhadas e ausências por colaborador.

O segundo relatório permite filtrar colaborador, datas e tipo de ausência, além de exportar o resumo e os detalhes em CSV. Essa atualização não exige novo SQL quando a versão 2.8 do banco já foi instalada.


## Atualização v2.11

Consulte `CHANGELOG_v2.11.md` e `INSTRUCOES_ATUALIZACAO_v2.11.txt`.
