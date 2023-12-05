# Development

## Laravel
alias sail='[ -f sail ] && bash sail || bash vendor/bin/sail'

## Packages
alias release='npm run release -- -r minor'
alias publish='npm run release:publish'

# Linux security
alias open_connections='netstat -tulpn'
alias running_services='systemctl list-units --type=service --state=running'


# Utils

## Docker
alias docker_clean='docker system prune'
