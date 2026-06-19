# dotfiles-sync

Dotfiles 双向同步工具。用配置文件驱动，在本机配置和 git 仓库之间同步；同步前会先对比差异、显示 diff，确认后再执行。

## 特性

- 配置文件驱动，声明式管理同步文件
- 同步前对比差异，显示 diff，确认后执行
- 内置 [age](https://github.com/FiloSottile/age) 加密/解密支持
- 同步文件统一存放在仓库 `home/` 目录

## 安装

### npm

```bash
npm install -g @jackgreen/dotfiles-sync
```

或直接运行：

```bash
npx @jackgreen/dotfiles-sync --help
```

### Homebrew

```bash
brew tap JackFGreen/tap
brew install dotfiles-sync
```

### 手动安装

```bash
git clone https://github.com/JackFGreen/dotfiles-sync.git
cd dotfiles-sync
echo "export PATH=\"$(pwd)/bin:\$PATH\"" >> ~/.zshrc
source ~/.zshrc
```

## 用法

### 首次使用

```bash
dotfiles-sync init
```

这会：
1. 生成 age 密钥对（如果不存在）
2. 提取公钥写入当前目录的 `.age-recipients`

### 配置

在你的 dotfiles 仓库根目录创建 `dotfiles-sync.conf`：

```bash
# 同步文件存放目录（相对于仓库根目录）
SYNC_DIR="home"

# 单个文件（cp 同步）
SYNC_FILES=(
  ".zshrc"
  ".config/xxx/xxx.json"
)

# 目录（rsync --delete 同步）
SYNC_DIRS=(
  ".zsh"
  ".config/xxx"
)

# rsync 排除规则
RSYNC_EXCLUDES=(
  "--exclude=.DS_Store"
  "--exclude=*.zwc"
  "--exclude=.git/"
)

# 加密文件（明文路径，密文自动为 路径.age）
# 需要先运行 dotfiles-sync init 生成 age 密钥对
ENCRYPTED_FILES=(
  ".zshrc.local"
)
```

### 同步到仓库

```bash
dotfiles-sync to-github
```

流程：
1. 自动加密 `ENCRYPTED_FILES` 中的明文文件
2. 对比差异，显示 diff
3. 确认后同步到仓库 `home/` 目录

### 同步到本机

```bash
dotfiles-sync to-local
```

流程：
1. 对比差异，显示 diff
2. 确认后同步到 `~/`
3. 自动解密 `.age` 文件为明文

### 只看差异

```bash
dotfiles-sync diff
```

只对比差异，不同步，不加密，不解密。

## 仓库结构

```
your-dotfiles-repo/
├── home/                    # 同步的配置文件
├── dotfiles-sync.conf       # 同步配置
├── .age-recipients          # age 公钥（init 生成）
└── ...
```

## 加密文件

加密文件使用 [age](https://github.com/FiloSottile/age) 加密。

- `to-github` 时自动加密明文 → `.age` 文件
- `to-local` 时自动解密 `.age` 文件 → 明文
- 公钥存储在仓库的 `.age-recipients`
- 私钥存储在 `~/.config/age/keys.txt`

## 依赖

- bash
- rsync
- [age](https://github.com/FiloSottile/age)（可选，仅加密功能需要）

## 开发

### 本地测试

```bash
# 克隆仓库
git clone https://github.com/JackFGreen/dotfiles-sync.git
cd dotfiles-sync

# 直接运行
bin/dotfiles-sync --help
bin/dotfiles-sync diff
```

### 发布新版本

```bash
# 1. 提交修改
git add .
git commit -m "feat: xxx"

# 2. 打 tag
git tag v0.1.1

# 3. 推送
git push origin main --tags

# 4. 发布到 npm
npm publish --access public

# 5. 更新 Homebrew Tap
# 计算新 SHA256
git archive --format=tar.gz --prefix=dotfiles-sync-0.1.1/ v0.1.1 -o /tmp/dotfiles-sync-0.1.1.tar.gz
shasum -a 256 /tmp/dotfiles-sync-0.1.1.tar.gz

# 更新 homebrew-tap/Formula/dotfiles-sync.rb 中的 url 和 sha256
# 提交并推送 homebrew-tap 仓库
```

## License

MIT
