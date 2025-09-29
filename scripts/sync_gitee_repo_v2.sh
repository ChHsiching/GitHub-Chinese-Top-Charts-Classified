#!/bin/bash

# Gitee到GitHub仓库同步脚本（改进版）
# 定期从Gitee克隆最新内容并同步到GitHub仓库
#
# 使用方法:
#   ./scripts/sync_gitee_repo_v2.sh      # 正常执行同步
#   ./scripts/sync_gitee_repo_v2.sh --safe  # 安全模式，只检查不执行
#   ./scripts/sync_gitee_repo_v2.sh -s     # 安全模式缩写

set -e  # 遇到错误立即退出

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    log "错误: $1"
    exit 1
}

# 配置变量
GITEE_REPO_URL="https://gitee.com/GrowingGit/GitHub-Chinese-Top-Charts.git"
TEMP_DIR="/tmp/gitee-repo-$(date +%s)"
BACKUP_BRANCH="gitee-backup"
LOG_FILE="sync.log"
SAFE_MODE=false  # 安全模式，只检查不执行

# 检查安全模式参数
if [ "$1" = "--safe" ] || [ "$1" = "-s" ]; then
    SAFE_MODE=true
    log "安全模式启用 - 只检查不执行实际同步"
fi

# 清理函数
cleanup() {
    log "清理临时文件..."
    rm -rf "$TEMP_DIR"
    # 清理sync.log文件
    if [ -f "sync.log" ]; then
        rm -f sync.log 2>/dev/null || true
    fi
    log "清理完成"
}

# 设置trap确保脚本退出时清理
trap cleanup EXIT

# 开始同步
log "=== 开始同步Gitee仓库 ==="
log "目标仓库: $GITEE_REPO_URL"

# 检查Git仓库状态
if [[ ! -d ".git" ]]; then
    handle_error "当前目录不是Git仓库"
fi

# 检查Git工作目录是否干净
if [[ -n "$(git status --porcelain)" ]]; then
    handle_error "工作目录不干净，请先提交或暂存更改"
fi

# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    CURRENT_BRANCH="main"  # 默认分支
fi
log "当前分支: $CURRENT_BRANCH"

# 检查是否在正确的分支上
if [ "$CURRENT_BRANCH" != "main" ]; then
    log "警告: 当前不在main分支上，可能会影响同步结果"
fi

# 克隆Gitee仓库
log "正在克隆Gitee仓库..."
if ! git clone --depth 1 "$GITEE_REPO_URL" "$TEMP_DIR"; then
    handle_error "克隆Gitee仓库失败"
fi
log "克隆完成"

# 如果是安全模式，只检查不执行
if [ "$SAFE_MODE" = true ]; then
    log "[安全模式] 检查Gitee仓库内容..."
    GITEE_FILES=$(find "$TEMP_DIR" -name "*.md" | wc -l)
    log "[安全模式] Gitee仓库包含 $GITEE_FILES 个Markdown文件"

    # 检查重要的本地文件
    IMPORTANT_FILES=(".gitignore" ".github" "CLAUDE.md" "scripts")
    for file in "${IMPORTANT_FILES[@]}"; do
        if [ -e "$file" ]; then
            log "[安全模式] 检测到重要本地文件: $file"
        fi
    done

    log "[安全模式] 检查完成，未执行实际操作"
    exit 0
fi

# 备份当前重要文件（在main分支操作）
log "备份重要文件..."
IMPORTANT_FILES=(".gitignore" ".github" "CLAUDE.md" "scripts")
PROTECTED_BACKUP_DIR="/tmp/protected_backup_$(date +%s)"
mkdir -p "$PROTECTED_BACKUP_DIR"

for file in "${IMPORTANT_FILES[@]}"; do
    if [ -e "$file" ]; then
        log "备份文件: $file"
        cp -r "$file" "$PROTECTED_BACKUP_DIR/" 2>/dev/null || true
    fi
done

# 检查备份分支是否存在
if git show-ref --verify --quiet "refs/heads/$BACKUP_BRANCH"; then
    log "备份分支已存在，删除后重新创建..."
    git branch -D "$BACKUP_BRANCH"
fi

# 创建新的备份分支
log "创建备份分支: $BACKUP_BRANCH"
git checkout --orphan "$BACKUP_BRANCH"

# 清理工作目录
git rm -rf . 2>/dev/null || true
log "清理工作目录完成"

# 复制Gitee内容（排除.git目录）
log "复制Gitee仓库内容..."
cp -r "$TEMP_DIR"/* . 2>/dev/null || true

# 恢复重要文件
log "恢复重要本地文件..."
for file in "${IMPORTANT_FILES[@]}"; do
    if [ -e "$PROTECTED_BACKUP_DIR/$(basename "$file")" ]; then
        log "恢复文件: $file"
        cp -r "$PROTECTED_BACKUP_DIR/$(basename "$file")" . 2>/dev/null || true
    fi
done

# 清理备份目录
rm -rf "$PROTECTED_BACKUP_DIR" 2>/dev/null || true

# 确保没有sync.log文件
if [ -f "sync.log" ]; then
    rm -f sync.log 2>/dev/null || true
fi

# 添加所有更改
log "添加文件到Git..."
git add .

# 提交更改
COMMIT_MSG="自动同步自Gitee仓库 - $(date '+%Y-%m-%d %H:%M:%S')

来源: $GITEE_REPO_URL
同步时间: $(date)"

log "提交更改..."
if ! git commit -m "$COMMIT_MSG"; then
    handle_error "提交失败"
fi
log "提交完成"

# 切换回主分支
log "切换回主分支: $CURRENT_BRANCH"
git checkout "$CURRENT_BRANCH"

# 合并备份分支
log "合并备份分支到主分支..."
if git merge --no-ff "$BACKUP_BRANCH" -m "合并Gitee同步: $(date '+%Y-%m-%d %H:%M:%S')" --allow-unrelated-histories; then
    log "合并成功"
else
    log "合并存在冲突，尝试解决..."

    # 显示冲突状态
    log "冲突文件："
    git diff --name-only --diff-filter=U

    # 解决冲突：优先采用备份分支（Gitee）版本
    git checkout --theirs .
    git add .
    git commit -m "合并Gitee同步(解决冲突): $(date '+%Y-%m-%d %H:%M:%S')"
    log "冲突已解决，采用Gitee版本"
fi

# 显示同步结果
log "=== 同步完成 ==="
log "最新提交:"
git log --oneline -n 3

# 显示文件统计
if command -v wc &> /dev/null; then
    TOTAL_FILES=$(find . -name "*.md" -not -path "./.git/*" | wc -l)
    log "Markdown文件总数: $TOTAL_FILES"
fi

log "同步脚本执行完成"
exit 0