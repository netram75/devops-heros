#!/usr/bin/env bash
# Session 3 - Shell Scripting task
# Netram (24BCS10329)
#
# Covers every requirement from the assignment:
#   - print the current date, the hostname and the username
#   - print the disk usage (df) and the running processes (ps)
#   - use variables and take user input with read -p
#   - create a directory with mkdir and a file with touch
#   - store the running processes in that file with > output redirection
set -u

# ---------- variables (filled by command substitution) ----------
current_date=$(date)
host_name=$(hostname)
user_name=$(whoami)
kernel_ver=$(uname -r)
session_count=$(who | wc -l)
disk_usage=$(df -h)
running_procs=$(ps aux --sort=-%cpu | head -n 10)

echo "===== System information ====="
echo "Date:      $current_date"
echo "Hostname:  $host_name"
echo "User:      $user_name"
echo "Kernel:    $kernel_ver"
echo "Sessions:  $session_count logged-in session(s)"
echo

echo "===== Disk usage (df -h) ====="
echo "$disk_usage"
echo

echo "===== Running processes (ps aux, busiest first) ====="
echo "$running_procs"
echo

# ---------- take input ----------
read -rp "Enter your name: " name
read -rp "Enter your roll number: " roll_no
read -rp "Enter a comment: " comment
read -rp "Enter a directory name to create: " dir_name
read -rp "Enter a file name for the process log: " file_name
echo

# ---------- create a directory, a file inside it, then fill it with > ----------
mkdir -p "$dir_name"
log_path="$dir_name/$file_name"
touch "$log_path"
ps -ef > "$log_path"

# ---------- print what was entered ----------
echo "===== Details entered ====="
echo "Name:      $name"
echo "Roll no:   $roll_no"
echo "Comment:   $comment"
echo

# ---------- report on the file we created ----------
echo "===== Process log ====="
echo "Directory created: $dir_name"
echo "File created:      $log_path"
echo "Wrote $(wc -l < "$log_path") lines to $log_path"
echo
echo "First 5 lines of $log_path:"
head -5 "$log_path"
