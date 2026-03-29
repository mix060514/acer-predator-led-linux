# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案目標

在 Linux 上控制 **Acer Predator Helios 500 PH517-52** 的非鍵盤燈光（Logo、機身燈條），目標是能在開機時自動關閉這些燈。

## 編譯與載入

```bash
# 編譯 kernel module
make

# 載入（需要 Secure Boot 關閉）
sudo insmod acer_wmi_tester.ko

# 卸載
sudo rmmod acer_wmi_tester

# 清除編譯產物
make clean
```

## 已解決：關燈方案

### 手動關燈
```bash
sudo insmod ~/pj/cc/acer_wmi_tester.ko 2>/dev/null
sudo bash ~/pj/cc/led_off.sh
```

`led_off.sh` 透過 WMID_GUID4 呼叫多個 WMI method（含 GET 和 SET），會關閉 Logo 及機身燈條。確認有效。

### 開機自動關燈（systemd）

```bash
sudo cp /etc/systemd/system/acer-led-off.service /etc/systemd/system/  # 若已存在則跳過
sudo systemctl daemon-reload
sudo systemctl enable acer-led-off.service
sudo systemctl start acer-led-off.service
sudo systemctl status acer-led-off.service
```

Service 檔案位置：`/etc/systemd/system/acer-led-off.service`
內容參考：`led_off_boot.sh`（insmod 模組後執行 led_off.sh）

## 已知架構

### 系統環境
- 已安裝 `facer` kernel module（`/opt/turbo-fan/`），這是 `acer-predator-turbo-and-rgb-keyboard-linux-module` 的自訂版本
- `facer` 掛載在 `platform:acer-wmi`，使用 **WMID_GUID4** = `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`
- PH517-52 的 quirks 只有 `turbo=1`，facer **沒有**實作非鍵盤 LED 控制
- Secure Boot 已關閉（BIOS 設定）

### WMI 介面（WMID_GUID4）
`acer_wmi_tester.c` 透過 `/proc/acer_wmi_tester` 暴露原始 WMI 呼叫介面：

```bash
# 格式：echo "GUID_INDEX METHOD_ID INPUT_HEX" > /proc/acer_wmi_tester
echo "0 4 1" > /proc/acer_wmi_tester && cat /proc/acer_wmi_tester
```

### 已確認的 Method ID（WMID_GUID4）
| Method ID | 名稱 | 說明 |
|-----------|------|------|
| 2 | SetGamingLED | Turbo 按鈕 LED |
| 4 | GetGamingLED | 讀 LED 類型 |
| 5 | GetGamingSysInfo | 系統資訊 |
| 6 | SetGamingStaticLED | 鍵盤靜態 RGB |
| 14 | SetGamingFanBehavior | 風扇模式控制 |
| 20 | SetGamingKBBL | 鍵盤動態 RGB |
| 21 | GetGamingKBBL | 讀鍵盤 RGB |
| 22 | SetGamingMiscSetting | 雜項設定 |
| 23 | GetGamingMiscSetting | 讀雜項設定 |

## 檔案說明

| 檔案 | 說明 |
|------|------|
| `acer_wmi_tester.c` | Kernel module 原始碼 |
| `led_off.sh` | **關燈腳本（有效）** |
| `led_off_boot.sh` | 開機腳本（insmod + led_off.sh）|
| `archive/` | 舊測試腳本與結果備份 |
