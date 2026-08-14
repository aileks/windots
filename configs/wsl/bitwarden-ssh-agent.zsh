export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"

if ! ss -xl | grep -Fq "$SSH_AUTH_SOCK"; then
  mkdir -p "$(dirname "$SSH_AUTH_SOCK")"
  chmod 700 "$(dirname "$SSH_AUTH_SOCK")"
  rm -f "$SSH_AUTH_SOCK"
  if [[ -x "$HOME/.local/bin/npiperelay.exe" ]] && command -v socat > /dev/null; then
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork,mode=600 \
      EXEC:"$HOME/.local/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork \
      > /dev/null 2>&1 &)
  fi
fi
