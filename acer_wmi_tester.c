// SPDX-License-Identifier: GPL-2.0
/*
 * Acer WMI Gaming LED 測試模組 v2
 * 支援多個 GUID，用於探測非鍵盤 LED 控制的正確 method ID
 *
 * 用法:
 *   寫入: echo "GUID_INDEX METHOD_ID INPUT_HEX" > /proc/acer_wmi_tester
 *   讀取: cat /proc/acer_wmi_tester
 *
 *   GUID_INDEX:
 *     0 = GUID4   7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 (已知 gaming)
 *     1 = GUID_BE 79772EC5-04B1-4BFD-843C-61E7F77B6CC9
 *     2 = GUID_BF 79772EC6-04B1-4BFD-843C-61E7F77B6CC9
 *     3 = GUID_BG 77B0C3A7-F71D-43CB-B749-91CBFF5DDC43
 *     4 = GUID_BK F75F5666-B8B3-4A5D-A91C-7488F62E5637
 *     5 = GUID_BL FE1DBBDA-3014-4856-870C-5B3A744BF341
 *
 * 範例:
 *   echo "0 4 1" > /proc/acer_wmi_tester   # GUID4, GetGamingLED(1)
 *   echo "1 1 1" > /proc/acer_wmi_tester   # GUID_BE, method 1, index 1
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/acpi.h>

#define MODULE_NAME "acer_wmi_tester"

static const char *guid_table[] = {
	[0] = "7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56", /* GUID4 - known gaming */
	[1] = "79772EC5-04B1-4BFD-843C-61E7F77B6CC9", /* obj=BE */
	[2] = "79772EC6-04B1-4BFD-843C-61E7F77B6CC9", /* obj=BF */
	[3] = "77B0C3A7-F71D-43CB-B749-91CBFF5DDC43", /* obj=BG */
	[4] = "F75F5666-B8B3-4A5D-A91C-7488F62E5637", /* obj=BK */
	[5] = "FE1DBBDA-3014-4856-870C-5B3A744BF341", /* obj=BL */
};
#define NUM_GUIDS 6

static struct proc_dir_entry *proc_entry;

static u32  last_guid_idx    = 0;
static u32  last_method_id   = 0;
static u64  last_input_val   = 0;
static u64  last_output_val  = 0;
static int  last_output_type = 0;
static int  last_output_len  = 0;
static int  last_acpi_status = 0;

static ssize_t proc_read(struct file *file, char __user *buf,
			 size_t count, loff_t *pos)
{
	char tmp[512];
	int len;

	if (*pos > 0)
		return 0;

	len = snprintf(tmp, sizeof(tmp),
		"guid_idx  : %u (%s)\n"
		"method_id : %u\n"
		"input     : 0x%016llx (%llu)\n"
		"output    : 0x%016llx (%llu)\n"
		"out_type  : %d  out_len: %d\n"
		"status    : %s (%d)\n",
		last_guid_idx,
		(last_guid_idx < NUM_GUIDS) ? guid_table[last_guid_idx] : "?",
		last_method_id,
		last_input_val, last_input_val,
		last_output_val, last_output_val,
		last_output_type, last_output_len,
		last_acpi_status == 0 ? "SUCCESS" : "FAILURE",
		last_acpi_status);

	if (copy_to_user(buf, tmp, len))
		return -EFAULT;

	*pos = len;
	return len;
}

static ssize_t proc_write(struct file *file, const char __user *buf,
			  size_t count, loff_t *pos)
{
	char kbuf[64] = {0};
	u32 guid_idx, method_id;
	unsigned long long input_val;
	u64 input;
	acpi_status status;
	struct acpi_buffer input_buf  = { sizeof(input), &input };
	struct acpi_buffer output_buf = { ACPI_ALLOCATE_BUFFER, NULL };
	const char *guid;

	if (count >= sizeof(kbuf))
		return -EINVAL;

	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;

	if (sscanf(kbuf, "%u %u %lli", &guid_idx, &method_id, &input_val) != 3) {
		pr_err(MODULE_NAME ": 格式錯誤，請用 \"GUID_IDX METHOD_ID INPUT_HEX\"\n");
		return -EINVAL;
	}

	if (guid_idx >= NUM_GUIDS) {
		pr_err(MODULE_NAME ": guid_idx 超出範圍 (0-%d)\n", NUM_GUIDS - 1);
		return -EINVAL;
	}

	guid = guid_table[guid_idx];
	if (!wmi_has_guid(guid)) {
		pr_warn(MODULE_NAME ": GUID[%u] %s 不存在\n", guid_idx, guid);
		last_guid_idx   = guid_idx;
		last_method_id  = method_id;
		last_input_val  = (u64)input_val;
		last_output_val = 0;
		last_acpi_status = -ENODEV;
		return count;
	}

	last_guid_idx   = guid_idx;
	last_method_id  = method_id;
	last_input_val  = (u64)input_val;
	last_output_val = 0;
	last_output_type = 0;
	last_output_len  = 0;
	input            = (u64)input_val;

	pr_info(MODULE_NAME ": GUID[%u] method=%u input=0x%016llx\n",
		guid_idx, method_id, last_input_val);

	status = wmi_evaluate_method(guid, 0, method_id,
				     &input_buf, &output_buf);

	if (ACPI_FAILURE(status)) {
		last_acpi_status = -(int)status;
		pr_warn(MODULE_NAME ": WMI call failed, ACPI status=0x%x\n", status);
	} else {
		last_acpi_status = 0;

		if (output_buf.pointer) {
			union acpi_object *obj = output_buf.pointer;
			last_output_type = obj->type;

			if (obj->type == ACPI_TYPE_INTEGER) {
				last_output_val = obj->integer.value;
				last_output_len = 8;
			} else if (obj->type == ACPI_TYPE_BUFFER) {
				last_output_len = obj->buffer.length;
				if (obj->buffer.length >= 8)
					last_output_val = *(u64 *)obj->buffer.pointer;
				else if (obj->buffer.length >= 4)
					last_output_val = *(u32 *)obj->buffer.pointer;
				else if (obj->buffer.length >= 2)
					last_output_val = *(u16 *)obj->buffer.pointer;
				else if (obj->buffer.length >= 1)
					last_output_val = *(u8 *)obj->buffer.pointer;
			}

			pr_info(MODULE_NAME ": output type=%d len=%d val=0x%016llx\n",
				last_output_type, last_output_len, last_output_val);
			kfree(output_buf.pointer);
		}
	}

	return count;
}

static const struct proc_ops proc_fops = {
	.proc_read  = proc_read,
	.proc_write = proc_write,
};

static int __init acer_wmi_tester_init(void)
{
	int i;

	pr_info(MODULE_NAME ": 可用 GUID 清單：\n");
	for (i = 0; i < NUM_GUIDS; i++) {
		pr_info(MODULE_NAME ":   [%d] %s %s\n", i, guid_table[i],
			wmi_has_guid(guid_table[i]) ? "(found)" : "(NOT found)");
	}

	proc_entry = proc_create(MODULE_NAME, 0666, NULL, &proc_fops);
	if (!proc_entry) {
		pr_err(MODULE_NAME ": 無法建立 /proc/%s\n", MODULE_NAME);
		return -ENOMEM;
	}

	pr_info(MODULE_NAME ": 已載入 /proc/%s\n", MODULE_NAME);
	return 0;
}

static void __exit acer_wmi_tester_exit(void)
{
	proc_remove(proc_entry);
	pr_info(MODULE_NAME ": 已卸載\n");
}

module_init(acer_wmi_tester_init);
module_exit(acer_wmi_tester_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Acer LED Research");
MODULE_DESCRIPTION("Acer WMI 多 GUID 測試工具 v2");
