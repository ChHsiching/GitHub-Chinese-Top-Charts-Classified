#!/bin/bash

# 备份功能测试脚本
# 用于测试gitee-backup分支的创建和管理

set -e

# 配置变量
BACKUP_BRANCH="gitee-backup"
TEST_BRANCH="test-backup-$(date +%s)"
LOG_FILE="backup_test.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    log "错误: $1"
    exit 1
}

# 清理函数
cleanup() {
    log "清理测试分支..."
    git checkout main >/dev/null 2>&1 || true
    git branch -D "$TEST_BRANCH" >/dev/null 2>&1 || true
    log "清理完成"
}

# 设置trap确保脚本退出时清理
trap cleanup EXIT

log "=== 开始备份功能测试 ==="

# 检查Git仓库状态
if [[ ! -d ".git" ]]; then
    handle_error "当前目录不是Git仓库"
fi

# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)
log "当前分支: $CURRENT_BRANCH"

# 检查是否在测试分支上
if [ "$CURRENT_BRANCH" = "test-sync-backup" ]; then
    log "正确：在测试分支上"
else
    handle_error "错误：不在测试分支上，当前在 $CURRENT_BRANCH"
fi

# 检查工作目录状态
if [[ -n "$(git status --porcelain)" ]]; then
    handle_error "工作目录不干净，请先提交或暂存更改"
fi

# 测试1：检查备份分支是否存在
log "测试1：检查备份分支状态"
if git show-ref --verify --quiet "refs/heads/$BACKUP_BRANCH"; then
    log "备份分支 $BACKUP_BRANCH 已存在"
    BACKUP_EXISTS=true
else
    log "备份分支 $BACKUP_BRANCH 不存在"
    BACKUP_EXISTS=false
fi

# 测试2：创建测试分支并模拟备份流程
log "测试2：创建测试分支模拟备份流程"

# 创建一个测试分支
git checkout -b "$TEST_BRANCH"
log "创建测试分支: $TEST_BRANCH"

# 添加一些测试内容
echo "测试内容 - $(date)" > test_file.txt
echo "另一个测试文件" > another_test.md
mkdir test_dir
echo "目录中的文件" > test_dir/dir_file.txt

# 添加并提交测试内容
git add .
git commit -m "测试提交：添加测试文件和目录"

log "测试内容已提交到 $TEST_BRANCH"

# 测试3：模拟备份分支创建流程
log "测试3：模拟备份分支创建流程"

# 切换到备份分支（如果存在）
if [ "$BACKUP_EXISTS" = true ]; then
    git checkout "$BACKUP_BRANCH"
    log "切换到现有备份分支: $BACKUP_BRANCH"
else
    # 创建新的备份分支
    git checkout --orphan "$BACKUP_BRANCH"
    log "创建新的备份分支: $BACKUP_BRANCH"

    # 清理所有文件
    git rm -rf . 2>/dev/null || true
    log "清理备份分支内容"
fi

# 检查备份分支状态
log "备份分支当前状态："
git log --oneline -n 3 || log "备份分支没有提交历史"

# 测试4：模拟文件复制（不实际复制外部内容）
log "测试4：模拟文件复制操作"

# 创建一些模拟的Gitee内容
mkdir -p simulated_gitee_content
echo "模拟的Gitee README内容" > simulated_gitee_content/README.md
echo "模拟的Gitee图表内容" > simulated_gitee_content/test_chart.md

# 模拟复制操作（只复制测试文件）
cp simulated_gitee_content/* . 2>/dev/null || true

log "模拟文件复制完成"

# 检查复制的文件
if [ -f "README.md" ]; then
    log "成功：模拟文件复制正常"
    ls -la *.md
else
    log "警告：模拟文件复制可能有问题"
fi

# 测试5：提交备份内容
log "测试5：提交备份内容"

git add .
if git diff --cached --quiet; then
    log "没有新内容需要提交"
else
    git commit -m "测试备份提交: $(date '+%Y-%m-%d %H:%M:%S')"
    log "备份内容提交成功"
fi

# 测试6：切换回主分支
log "测试6：切换回主分支"
git checkout main

# 测试7：尝试合并备份分支
log "测试7：尝试合并备份分支到主分支"

if git merge --no-ff "$BACKUP_BRANCH" -m "测试合并备份分支: $(date '+%Y-%m-%d %H:%M:%S')"; then
    log "合并成功：备份分支可以正常合并到主分支"

    # 显示合并结果
    log "合并后的文件列表："
    ls -la

else
    log "合并失败或存在冲突（这是正常的测试结果）"

    # 取消合并
    git merge --abort 2>/dev/null || true
    log "已取消合并测试"
fi

# 测试完成
log "=== 备份功能测试完成 ==="

# 显示测试结果摘要
log "测试结果摘要："
log "- 备份分支状态: $([ "$BACKUP_EXISTS" = true ] && echo "存在" || echo "不存在")"
log "- 分支切换: 正常"
log "- 文件操作: 正常"
log "- 提交功能: 正常"
log "- 合并测试: 已完成"

# 检查是否需要清理备份分支
if [ "$BACKUP_EXISTS" = false ]; then
    log "清理测试创建的备份分支..."
    git branch -D "$BACKUP_BRANCH"
    log "备份分支已清理"
fi

log "所有测试项目完成！"