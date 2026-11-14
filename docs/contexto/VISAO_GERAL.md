# Visão geral

## O que é
**AVA Sync** é um app Android (Flutter) que leva o AVA do Ifes (Moodle,
`https://ava3.cefor.ifes.edu.br`) para o celular: prazos, atividades, provas, avisos,
materiais offline, notas e envio de atividades. Também lê boletim, diários (frequência)
e horário do **Q-Acadêmico** e tem a área **Social** (grupos e chat entre colegas).

## Para quem
Um grupo pequeno de estudantes do Ifes (BSI). Não é um produto do campus inteiro.
O dono do repositório decide o que entra.

## Princípios
1. **Funciona sozinho no celular.** Sem servidor próprio para o AVA; distribuição pelo
   GitHub Releases. O único backend é o do Social (Supabase).
2. **Dados da pessoa ficam com ela.** Tokens e senhas só no armazenamento seguro do
   aparelho. Nada de dado pessoal no Git, em logs ou em serviços de terceiros.
3. **Respeitar os sistemas da instituição.** Só APIs oficiais do Moodle; o Q-Acadêmico
   é lido pelo WebView com o login da própria pessoa, sem burlar proteção anti-robô.
4. **Atualizar sem dor.** O app se atualiza sozinho, por cima, sem perder dados
   (mesma assinatura e mesmo `applicationId` sempre).
5. **Bonito e fácil.** Interface em português, colorida, com estados de carregando,
   vazio e erro bem explicados.
