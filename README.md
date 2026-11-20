# GestFast (Flutter)

Porte do GestFast v1 (1.3.0) para Flutter/Dart, com os bugs do v1 corrigidos. **A interface é fiel à do v1**: mesmas telas, textos, cores, emojis, tabelas e layout (referência: `public/` e `style.css` do projeto v1). O projeto é só local: não há repositório no GitHub.

```
backend/   servidor Node.js + MySQL, com as correções (mesmo banco do v1, sem migração)
app/       app Flutter: Android, iOS, Web, Windows, macOS e Linux
```

O app não acessa o MySQL diretamente: ele fala com o `backend/` pela API, para a senha do banco não ficar dentro do app.

## Como rodar

O Flutter deste projeto é o da versão **3.47.9**, em `C:\dev\flutter`. O `flutter` do PATH ainda é a versão antiga (`C:\flutter`, 3.19.3), que não compila este app. Use o caminho completo, como nos comandos abaixo. O VS Code já usa o SDK certo quando você abre a pasta `GestFast-Flutter` (`.vscode/settings.json`).

### 1. Backend

```powershell
cd backend
copy .env.example .env    # coloque a senha do seu MySQL no .env
npm install
npm start                 # http://localhost:3000
```

Pode usar o banco `gestfast` que você já tem: o esquema não mudou. Para um banco novo, rode `database/schema.sql` e `database/seed.sql` no Workbench. **O `schema.sql` apaga o banco `gestfast` existente.**

Usuários do `seed.sql`: `proprietario@padarianovayork.com` / `admin123`, `backoffice@padarianovayork.com` / `backoffice123` e `henry@padarianovayork.com` / `func123`.

Para o celular alcançar o servidor, coloque `HOST=0.0.0.0` no `.env` e use o IP do computador na tela de login do app, como `http://192.168.0.10:3000`. O firewall do Windows pode pedir permissão.

### Pelo VS Code

Abra a pasta `GestFast-Flutter`, vá em **Run and Debug** (`Ctrl+Shift+D`), escolha **GestFast (servidor + app web)** e aperte `F5`. Isso sobe o servidor na porta 3001 e o app no Edge, já ligados. O `backend/.env` precisa existir, com a senha do MySQL.

### 2. App na web

```powershell
cd app
C:\dev\flutter\bin\flutter build web --release --no-web-resources-cdn --pwa-strategy=none
```

Depois abra http://localhost:3000. O backend entrega o site de `app/build/web`, então é preciso gerar o build de novo sempre que o app mudar.

### 3. App nas outras plataformas

| Plataforma | Comando (na pasta `app`) | Precisa de |
|---|---|---|
| Windows | `C:\dev\flutter\bin\flutter build windows` | Modo de Desenvolvedor do Windows + Visual Studio com "Desenvolvimento para desktop com C++" |
| Android | `C:\dev\flutter\bin\flutter build apk` | Modo de Desenvolvedor do Windows + Android Studio com SDK e licenças aceitas (`flutter doctor --android-licenses`) |
| Linux | `flutter build linux` | Computador ou WSL com Linux, além de `libsecret` |
| iOS | `flutter build ipa` | Mac com Xcode e conta Apple Developer para publicar |
| macOS | `flutter build macos` | Mac com Xcode |

No login dos apps nativos, informe o endereço do servidor. No emulador Android, use `http://10.0.2.2:3000`. Fora da rede local, o app exige `https://`.

## Testes

```powershell
cd backend
npm test                                  # 42 testes; usa o banco gestfast_test, nunca o gestfast
cd ..\app
C:\dev\flutter\bin\flutter test           # testes do app
C:\dev\flutter\bin\flutter analyze
```

## Bugs do v1 corrigidos

Cada um tem teste automatizado em `backend/test/regressao.test.js` ou em `app/test/`.

**Dados**
1. Salvar um produto sobrescrevia o estoque com o valor da tela, sem histórico. Agora o saldo só muda por movimentação, e o estoque inicial entra no histórico.
2. A conferência enviava todos os produtos e desfazia vendas feitas durante a contagem. Agora vai só o que foi contado, e o servidor recusa se o saldo mudou.
3. Editar venda em dinheiro deixava recebido e troco errados.
4. Editar venda com o mesmo produto em dois preços juntava tudo no primeiro preço.
5. Editar venda aceitava incluir produto inativo.

**Servidor e segurança**
6. Endereço malformado (como `/%E0%A4%A`) derrubava o servidor.
7. Erro interno respondia 400 com a mensagem crua do SQL e não ia para o log.
8. Corpo JSON `null` ou item nulo expunha erro interno.
9. O link de redefinição de senha ficava visível na tela de Logs. Agora o código sai só no console do servidor.
10. A senha de gerente não tinha limite de tentativas.
11. Trocar a senha não encerrava as outras sessões.
12. O tempo de resposta do login revelava se o e-mail existia.
13. A checagem de pasta dos arquivos estáticos aceitava pastas com prefixo igual.

**Validação**
14. Datas impossíveis (31/02) e filtros inválidos estouravam no MySQL.
15. Quantidade como 0,0001 arredondava para zero e estourava no banco.
16. Produto inválido deixava imagem órfã.
17. Vendas simultâneas podiam travar entre si (deadlock).
18. Ajuste de conferência usava preço de venda nas saídas. Agora usa sempre o custo.
19. O texto `"false"` ativava as simulações em Configuração.
20. Os bloqueios de login nunca eram limpos da memória.

**Encontrados além da lista planejada**
- `POST /api/products` com `id_produto` no corpo alterava o produto existente, e o cliente podia definir o caminho da imagem.
- Valores muito grandes de preço e quantidade estouravam as colunas do banco.

**Telas (resolvidos no app novo)**
21. Mudar o filtro na conferência apagava as contagens digitadas.
22. A quantidade sugerida na requisição não voltava depois de editada.
23. Quantidade negativa ao editar venda removia o item sem avisar.
24. A mensagem verde de sucesso no login continuava verde no erro seguinte.
25. A previsão de entrega usava a data do aparelho, não a do servidor.
26. Botões levavam a telas sem permissão.

## O que mudou no funcionamento

- A API aceita `Authorization: Bearer`. O token só é entregue a quem envia `X-Client: app`; no navegador continua o cookie HttpOnly.
- O servidor não entrega mais o front HTML antigo, só o build do Flutter. O front antigo continua no projeto v1.
- "Esqueci minha senha": sem e-mail configurado, o código aparece no console do servidor e é digitado na tela de redefinição do app.

## Limitações conhecidas

- O app precisa do servidor: não há modo offline, igual ao v1.
- O gráfico do painel soma kg com unidades, herdado do v1. Mudar isso é uma decisão de regra de negócio.
- Na web, a fonte é a Roboto embutida (no v1 no Windows era a Segoe UI, que não pode ser distribuída), e os emojis são os da Noto Color Emoji. Emojis digitados em uma descrição, fora dos que o sistema usa, aparecem como quadradinho, porque o app não baixa fontes de fora. Nos apps nativos valem a fonte e os emojis do sistema.
- Android: o sistema não permite liberar HTTP só para a rede local. O arquivo `network_security_config.xml` libera HTTP, e quem restringe à rede local é o próprio app (`validarServidor`).
