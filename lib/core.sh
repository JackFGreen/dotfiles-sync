#!/usr/bin/env bash

# dotfiles-sync 核心函数库

# ========== 配置加载 ==========

load_config() {
  local repo_dir="$1"
  local conf_file="${repo_dir}/dotfiles-sync.conf"

  if [[ ! -f "$conf_file" ]]; then
    echo "错误：找不到配置文件 ${conf_file}"
    return 1
  fi

  # 设置默认值
  SYNC_DIR="${SYNC_DIR:-home}"
  SYNC_FILES=()
  SYNC_DIRS=()
  RSYNC_EXCLUDES=()
  ENCRYPTED_FILES=()

  # shellcheck source=/dev/null
  source "$conf_file"

  # 配置路径
  SYNC_TARGET_DIR="${repo_dir}/${SYNC_DIR}"
  AGE_RECIPIENTS_FILE="${repo_dir}/.age-recipients"
}

# ========== 验证 ==========

validate_repo_dir() {
  local repo_dir="$1"

  repo_dir="${repo_dir:-$(pwd)}"
  repo_dir="${repo_dir/#\~/${HOME}}"

  if [[ ! -d "${repo_dir}" ]]; then
    echo "错误：目录不存在：${repo_dir}"
    return 1
  fi

  if [[ ! -f "${repo_dir}/dotfiles-sync.conf" ]]; then
    echo "错误：目录下找不到 dotfiles-sync.conf：${repo_dir}"
    return 1
  fi

  echo "${repo_dir}"
}

check_age() {
  if ! command -v age &>/dev/null; then
    echo "错误：未安装 age，请先运行 brew install age"
    return 1
  fi
}

# ========== 差异对比 ==========

has_diff_file() {
  local file1="$1"
  local file2="$2"
  if [[ ! -f "$file2" ]]; then
    return 0
  fi
  ! diff -q "$file1" "$file2" >/dev/null 2>&1
}

has_diff_dir() {
  local dir1="$1"
  local dir2="$2"
  if [[ ! -d "$dir2" ]]; then
    return 0
  fi
  ! diff -rq "$dir1" "$dir2" >/dev/null 2>&1
}

# ========== 交互 ==========

confirm_action() {
  local message="$1"
  local reply
  read -r -p "${message} [y/N] " reply || true
  case "${reply}" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ========== 目录创建 ==========

create_target_dirs() {
  local target_dir="$1"
  local file
  local dir

  for file in "${SYNC_FILES[@]+"${SYNC_FILES[@]}"}"; do
    mkdir -p "${target_dir}/$(dirname "$file")"
  done

  for dir in "${SYNC_DIRS[@]+"${SYNC_DIRS[@]}"}"; do
    mkdir -p "${target_dir}/${dir}"
  done

  # 为加密文件创建目录
  for file in "${ENCRYPTED_FILES[@]+"${ENCRYPTED_FILES[@]}"}"; do
    mkdir -p "${target_dir}/$(dirname "$file")"
  done
}

# ========== 同步 ==========

sync_single_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if has_diff_file "$src" "$dest"; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    echo "已同步 $label"
    return 0
  fi
  return 1
}

sync_directory() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if has_diff_dir "$src" "$dest"; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$src/" "$dest/"
    echo "已同步 $label"
    return 0
  fi
  return 1
}

# ========== 加密/解密 ==========

encrypt_file() {
  local plaintext="$1"
  local recipients_file="$2"

  if [[ ! -f "$plaintext" ]]; then
    return 1
  fi

  if [[ ! -f "$recipients_file" ]]; then
    echo "错误：找不到公钥文件 ${recipients_file}"
    return 1
  fi

  local encrypted="${plaintext}.age"
  age -R "$recipients_file" -o "$encrypted" "$plaintext"
}

decrypt_file() {
  local encrypted="$1"
  local output="$2"

  if [[ ! -f "$encrypted" ]]; then
    return 1
  fi

  age -d -o "$output" "$encrypted"
}
