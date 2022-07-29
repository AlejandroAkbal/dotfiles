
# Development
alias sail='[ -f sail ] && bash sail || bash vendor/bin/sail'

## Packages
alias release='npm run release -- -r minor'
alias publish='npm run release:publish'

## Python
alias pyenv='python3 -m venv ./venv'
alias pyenv_a='source ./venv/bin/activate'
