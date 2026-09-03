#!/bin/sh
set -e

if [ -z "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
  echo "Erreur: ce dossier n'est pas un dépôt Git."
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: ./git-sync.sh \"Message de commit\""
  exit 1
fi

branch=$(git branch --show-current)
if [ -z "$branch" ]; then
  echo "Erreur: impossible de déterminer la branche actuelle."
  exit 1
fi

echo "Synchronisation sur la branche $branch..."

git pull --rebase origin "$branch"

git add -A

git commit -m "$1" || true

git push origin "$branch"

echo "Synchronisation terminée vers GitHub sur $branch."
