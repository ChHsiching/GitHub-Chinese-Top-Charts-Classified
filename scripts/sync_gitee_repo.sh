#!/bin/bash

# Gitee到GitHub仓库同步脚本
# 定期从Gitee克隆最新内容并同步到GitHub仓库
#
# 使用方法:
#   ./scripts/sync_gitee_repo.sh      # 正常执行同步
#   ./scripts/sync_gitee_repo.sh --safe  # 安全模式，只检查不执行
#   ./scripts/sync_gitee_repo.sh -s     # 安全模式缩写
#
# 安全模式可以用来:
#   - 测试Gitee仓库连接
#   - 检查文件结构
#   - 验证重要文件是否存在
#   - 避免意外修改本地仓库

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

# 检查备份分支是否存在，如果不存在则创建
if [ "$SAFE_MODE" = true ]; then
    if git show-ref --verify --quiet "refs/heads/$BACKUP_BRANCH"; then
        log "[安全模式] 检测到备份分支存在: $BACKUP_BRANCH"
    else
        log "[安全模式] 将创建新的备份分支: $BACKUP_BRANCH"
    fi
else
    if git show-ref --verify --quiet "refs/heads/$BACKUP_BRANCH"; then
        log "切换到备份分支: $BACKUP_BRANCH"
        git checkout "$BACKUP_BRANCH"
    else
        log "创建新的备份分支: $BACKUP_BRANCH"
        git checkout --orphan "$BACKUP_BRANCH"
        git rm -rf .  # 清理所有文件，但保留分支
        # 保留重要的配置文件
        if [ -f "$TEMP_DIR/.gitignore" ]; then
            cp "$TEMP_DIR/.gitignore" . 2>/dev/null || true
        fi
    fi
fi

# 复制Gitee仓库内容（保留重要的本地配置）
log "正在复制Gitee仓库内容..."
if [ "$SAFE_MODE" = true ]; then
    log "[安全模式] 跳过文件复制和Git操作"

    # 只检查Gitee仓库内容
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

# 先备份重要的本地文件
IMPORTANT_FILES=(".gitignore" ".github" "CLAUDE.md" "scripts")
for file in "${IMPORTANT_FILES[@]}"; do
    if [ -e "$file" ]; then
        log "备份本地文件: $file"
        cp -r "$file" "/tmp/local_backup_$(basename "$file")-$(date +%s)" 2>/dev/null || true
    fi
done

# 复制Gitee内容，但跳过一些重要的配置目录
cp -r "$TEMP_DIR"/* . 2>/dev/null || true
cp -r "$TEMP_DIR"/.* . 2>/dev/null || true

# 确保保留重要的本地配置
if [ ! -f ".gitignore" ] && [ -f "/tmp/local_backup_gitignore-"* ]; then
    cp "/tmp/local_backup_gitignore-"* .gitignore 2>/dev/null || true
fi

# 添加所有更改
log "添加文件到Git..."
git add .

# 检查是否有更改
if git diff --cached --quiet; then
    log "没有检测到更改，无需提交"
else
    # 提交更改
    COMMIT_MSG="自动同步自Gitee仓库 - $(date '+%Y-%m-%d %H:%M:%S')

来源: $GITEE_REPO_URL
同步时间: $(date)"

    log "提交更改..."
    if ! git commit -m "$COMMIT_MSG"; then
        handle_error "提交失败"
    fi
    log "提交完成"
fi

# 切换回主分支
log "切换回主分支: $CURRENT_BRANCH"
git checkout "$CURRENT_BRANCH"

# 合并备份分支（仅在非安全模式下）
if [ "$SAFE_MODE" = false ]; then
    log "合并备份分支到主分支..."

    # 检查是否有实际需要合并的内容
    if git diff "$CURRENT_BRANCH" "$BACKUP_BRANCH" --quiet; then
        log "没有检测到差异，跳过合并"
    else
        # 尝试合并
        if git merge --no-ff "$BACKUP_BRANCH" -m "合并Gitee同步: $(date '+%Y-%m-%d %H:%M:%S')"; then
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
    fi
else
    log "[安全模式] 跳过合并操作"
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