ATUALIZAÇÃO COMPLETA — REDEFINIÇÃO DE SENHA
APLICATIVO APONTA HORAS
Versão da correção: 2026.08.03

============================================================
1. PROBLEMA IDENTIFICADO
============================================================

O link recebido por e-mail está abrindo o domínio antigo:

https://apontamentos-engmanufatura.rmacedo.workers.dev

Esse endereço retorna:

DNS_PROBE_FINISHED_NXDOMAIN

Isso significa que o endereço não existe mais no DNS. O código de
recuperação pode estar correto, mas o navegador não consegue chegar
ao aplicativo.

============================================================
2. ENDEREÇOS QUE DEVEM SER UTILIZADOS
============================================================

Endereço principal:
https://apontamentos-engmanufatura.modulardtc.workers.dev

Endereço secundário:
https://apontamentosengmanufatura.netlify.app

O aplicativo foi ajustado para usar o endereço em que estiver aberto,
por meio de:

window.location.origin

Assim, a recuperação não volta a quebrar caso o aplicativo seja
publicado no endereço principal ou secundário.

============================================================
3. ARQUIVOS DESTA ATUALIZAÇÃO
============================================================

COPIAR_PARA_O_PROJETO/
- redefinir-senha.html
- auth-recovery.js
- _redirects

INSTRUCOES/
- CONFIGURAR_SUPABASE.txt
- ALTERACOES_APP_JS.txt
- ALTERACOES_INDEX_HTML.txt
- SERVICE_WORKER_E_CACHE.txt
- TESTE_FINAL.txt

============================================================
4. COMO INSTALAR
============================================================

1. Faça uma cópia de segurança da pasta atual do aplicativo.

2. Copie os arquivos da pasta COPIAR_PARA_O_PROJETO para a raiz do
   projeto, junto de index.html, app.js, style.css e config.js.

3. Abra o arquivo app.js e aplique os dois trechos descritos em:

   INSTRUCOES/ALTERACOES_APP_JS.txt

4. Abra o index.html e aplique o trecho descrito em:

   INSTRUCOES/ALTERACOES_INDEX_HTML.txt

5. Configure as URLs no Supabase seguindo:

   INSTRUCOES/CONFIGURAR_SUPABASE.txt

6. Atualize a versão do cache do PWA, conforme:

   INSTRUCOES/SERVICE_WORKER_E_CACHE.txt

7. Publique novamente a pasta completa no Cloudflare ou no Netlify.

8. Pressione Ctrl + F5 no computador. No celular, feche e abra o
   aplicativo novamente.

9. Solicite um NOVO e-mail de redefinição. O e-mail antigo continuará
   apontando para o domínio antigo e não deverá ser utilizado.

============================================================
5. BANCO DE DADOS
============================================================

Não é necessário executar SQL.

Não substitua o seu config.js.

Não coloque a service_role key no navegador.

============================================================
6. RESULTADO ESPERADO
============================================================

Ao solicitar a redefinição:

1. O e-mail é enviado.
2. O link abre:
   /redefinir-senha.html
3. O usuário informa a nova senha.
4. A senha é alterada no Supabase.
5. O usuário retorna para a tela inicial do Aponta Horas.

============================================================
7. OBSERVAÇÃO IMPORTANTE
============================================================

Esta pasta contém a correção completa do fluxo de recuperação.
Para entregar o aplicativo inteiro já mesclado, é necessário aplicar
os trechos no app.js e index.html da versão que está atualmente
publicada, pois esses arquivos não estavam disponíveis neste envio.
