https://zitadel.com/docs/self-hosting/deploy/compose


1.

`
curl -L https://raw.githubusercontent.com/zitadel/zitadel/main/docs/docs/self-hosting/deploy/docker-compose.yaml -o docker-compose.yaml
`

2. `docker compose pull`
3. `docker compose up --detach --wait`
4. `docker compose ps`


Visit:  `http://localhost:8080/ui/console`
