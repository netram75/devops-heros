# Setup

This folder is a starting point for the DevOps Heros homework: all the course material,
plus an empty write-up template for every session's task. There is no git history and no
author identity in it yet - the first commit should be yours.

## 1. Make it yours

This folder is already a git repository with everything staged, but it has **no commits
and no author identity**. Set yours and make the first commit:

```bash
cd devops-heros                 # or wherever you put this folder

# your own name and email - these end up in every commit you make
git config user.name  "Your Name"
git config user.email "you@example.com"

git commit -m "Initial commit: course notes and task scaffolds"
```

(If you would rather start from scratch, delete the `.git` folder and run `git init -b main`
yourself - nothing else depends on it.)

## 2. Put your name in the write-ups

Each `task/README.md` starts with:

```markdown
- **Name:** _(your name)_
- **Enrollment No:** _(your enrollment number)_
```

Fill those in as you do each task. Do not leave the placeholders in a submission.

## 3. Publish it to your GitHub

With the [GitHub CLI](https://cli.github.com/):

```bash
gh auth login                   # once, if you have not already
gh repo create devops-heros --public --source=. --remote=origin --push
```

Or create an empty repo on github.com and then:

```bash
git remote add origin https://github.com/<your-username>/devops-heros.git
git push -u origin main
```

## 4. Working through a session

1. Read the session notes in the `sessionN-*/` folder.
2. Find the task in the homework doc (linked from the root [README](README.md)).
3. Actually run it - on WSL/Linux for the Linux, shell and networking sessions; with Docker
   for sessions 6–8; with minikube or kind for sessions 9–10.
4. Write up what you ran and what came back in `task/README.md`, and put your screenshots
   in `task/screenshots/`.
5. Commit as you go, one session at a time, rather than in a single big commit at the end.

## 5. What you need installed

| Sessions | Needs |
|---|---|
| 2, 3, 4, 5 | A Linux shell. On Windows: `wsl --install -d Ubuntu`. |
| 6–7, 8 | Docker (Docker Desktop on Windows/macOS, or Docker Engine on Linux). |
| 9, 10 | A local Kubernetes cluster: `minikube start --driver=docker`, or `kind`. |

Some sessions need tools that are not installed by default. On Ubuntu, session 4 needs:

```bash
sudo apt-get install dnsutils iputils-tracepath
```

## A few things that will save you time

- **Line endings.** The included `.gitattributes` forces LF. Without it, git on Windows
  commits CRLF and a shell script checked out on Linux fails with
  `bad interpreter: /usr/bin/env bash^M`.
- **Paste the real text output**, not only a screenshot. It is searchable, it survives a
  broken image, and it is much easier to check against.
- **Write down the errors you hit** and how you fixed them. That section of the template is
  the most useful part of the whole write-up when you come back to it.
- **Your screenshots should come from your own machine.** Hostnames, IPs, container IDs and
  timestamps are all visible in terminal output, so borrowed screenshots are obvious - and
  the point of the exercise is the run, not the picture.
