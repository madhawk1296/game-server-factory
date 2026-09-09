# Pelican server extension for Paymenter

Paymenter ships a Pterodactyl server extension but not a Pelican one. Pelican is
a Pterodactyl fork and the API is close, but two concepts were removed:

- `/api/application/locations` -- gone. Deployment targets a node directly.
- `/api/application/nests` -- gone. Eggs are a flat collection, so egg variables
  come from `/api/application/eggs/{id}?include=variables` rather than
  `/api/application/nests/{nest}/eggs/{egg}`.

`Pelican.php` is the shipped Pterodactyl extension with those three call sites
changed, renamed so Paymenter upgrades cannot clobber it. Everything else --
server creation, suspend, unsuspend, terminate, upgrade -- is untouched, because
those endpoints are identical between the two panels.

Installing it is not yet in Terraform:

```bash
docker cp Pelican.php paymenter:/app/extensions/Servers/Pelican/Pelican.php
docker exec paymenter chown -R nginx:nginx /app/extensions/Servers/Pelican
```

## Pelican API keys

Two things cost hours here and are not documented anywhere obvious:

- The `permissions` map uses **bare** resource names -- `server`, `node`, `user`,
  `egg` -- not Pterodactyl's `r_server` form. With the wrong keys every request
  returns 403 "This action is unauthorized" while the key itself is perfectly
  valid and the user is root admin, because `ApiKey::getPermission()` falls
  through to NONE.
- `ApiKey extends PersonalAccessToken`, and `token` is cast `encrypted`. Assign
  the plaintext and let the cast encrypt it; encrypting first double-encrypts
  and yields a 401.

Resource names come from `ApiKey::getPermissionList()`. Values are a bitmask:
1 read, 2 write, 3 both.
