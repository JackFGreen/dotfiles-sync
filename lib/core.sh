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

# age 私钥文件（解密对比时使用）
AGE_KEYS_FILE="${AGE_KEYS_FILE:-${HOME}/.config/age/keys.txt}"

# 把文件内容输出到 stdout；.age 文件先解密。
# 解密失败（缺私钥等）时回退为原始字节，保证对比仍可进行。
cat_or_decrypt() {
  local file="$1"
  if [[ "$file" == *.age && -f "$AGE_KEYS_FILE" ]]; then
    age -d -i "$AGE_KEYS_FILE" "$file" 2>/dev/null || cat "$file"
  else
    cat "$file"
  fi
}

has_diff_file() {
  local file1="$1"
  local file2="$2"
  if [[ ! -f "$file2" ]]; then
    return 0
  fi
  # 加密文件按明文对比：age 每次加密结果都不同，直接比字节会永远“有差异”
  if [[ "$file1" == *.age || "$file2" == *.age ]]; then
    ! diff -q <(cat_or_decrypt "$file1") <(cat_or_decrypt "$file2") >/dev/null 2>&1
    return
  fi
  ! diff -q "$file1" "$file2" >/dev/null 2>&1
}

# 生成单个文件的彩色 unified diff；.age 文件先解密再对比明文。
# 参数：旧文件 新文件 显示名
render_file_diff() {
  local old="$1"
  local new="$2"
  local name="$3"
  if [[ "$old" == *.age || "$new" == *.age ]]; then
    diff --color=always -u \
      --label "a/${name} (明文)" --label "b/${name} (明文)" \
      <(cat_or_decrypt "$old") <(cat_or_decrypt "$new") 2>/dev/null || true
  else
    diff --color=always -u "$old" "$new" 2>/dev/null || true
  fi
}

has_diff_dir() {
  local dir1="$1"
  local dir2="$2"
  if [[ ! -d "$dir2" ]]; then
    return 0
  fi
  ! diff -rq "$dir1" "$dir2" >/dev/null 2>&1
}

# 区块分隔横幅
section_banner() {
  printf '=========================================\n  %s\n=========================================' "$1"
}

# 计算差异并生成分区输出：加密文件在前，普通文件/目录在后。
# 参数：src_base dest_base 文件缺失提示 目录缺失提示
# 依赖（动态作用域）：all_files、SYNC_DIRS
# 输出（全局）：DIFF_OUTPUT、DIFF_NFILES、DIFF_NDIRS
compute_diff() {
  local src_base="$1" dest_base="$2" miss_file="$3" miss_dir="$4"
  local enc_out="" plain_out="" block=""
  local file dir src dest
  DIFF_NFILES=0
  DIFF_NDIRS=0

  # 对比单个文件
  for file in "${all_files[@]}"; do
    src="${src_base}/${file}"
    dest="${dest_base}/${file}"
    if has_diff_file "$src" "$dest"; then
      ((DIFF_NFILES++)) || true
      if [[ ! -f "$dest" ]]; then
        block="━━━ ~/${file} (${miss_file}) ━━━"$'\n'
      else
        block="━━━ ~/${file} ━━━"$'\n'
        block+="$(render_file_diff "$dest" "$src" "$file")"$'\n'
      fi
      block+=$'\n'
      if [[ "$file" == *.age ]]; then
        enc_out+="$block"
      else
        plain_out+="$block"
      fi
    fi
  done

  # 对比目录（普通文件区）
  for dir in "${SYNC_DIRS[@]+"${SYNC_DIRS[@]}"}"; do
    src="${src_base}/${dir}"
    dest="${dest_base}/${dir}"
    if has_diff_dir "$src" "$dest"; then
      ((DIFF_NDIRS++)) || true
      if [[ ! -d "$dest" ]]; then
        plain_out+="━━━ ~/${dir}/ (${miss_dir}) ━━━"$'\n'
      else
        plain_out+="━━━ ~/${dir}/ ━━━"$'\n'
        plain_out+="$(diff --color=always -ru "$dest" "$src" 2>/dev/null || true)"$'\n'
      fi
      plain_out+=$'\n'
    fi
  done

  DIFF_OUTPUT=""
  if [[ -n "$enc_out" ]]; then
    DIFF_OUTPUT+="$(section_banner "加密文件")"$'\n\n'
    DIFF_OUTPUT+="$enc_out"
  fi
  if [[ -n "$plain_out" ]]; then
    DIFF_OUTPUT+="$(section_banner "普通文件")"$'\n\n'
    DIFF_OUTPUT+="$plain_out"
  fi
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
