# Load pyenv automatically by appending
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Load pyenv-virtualenv automatically by adding
eval "$(pyenv virtualenv-init -)"
