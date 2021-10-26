# `traefik` role

This role will install & configure [Treafik](https://traefik.io) reverse-proxy.
It'll mainly be used with docker, to allow load-balancing between containers easily.

## Documentation

Documentation can be found at [Treafik documentation](https://docs.traefik.io/).

## Role configuration

Here are the default value:
```yaml
web_admin_port: 8080
default_entry_points: "\"http\", \"https\""
domain_name: this_should_be_set_on_playbook
```

It can be found here [vars/main.yml](vars/main.yml).

### Configuration when running playbook

Please use the following syntax to set specific values when including the role on a playbook:

```yaml
roles:
  - role: traefik
    web_admin_port: 1337
    default_entry_points: "http"
    domain_name: my.domain-name.com
```

### Registrating containers on Traefik

By default, Traefik will not register containers by default, unless they have the correct label (`traefik.enable=true`).

To be able to reach a container throught Traefik, the container should have the following labels:
```ini
traefik.backend = < backend-name >
traefik.port = < containter-exposed-port >
traefik.enable = true # if not set, it'll not be exposed at all
traefik.frontend.rule = Host:< domain-name >
```
