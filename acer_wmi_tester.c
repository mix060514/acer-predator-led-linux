// SPDX-License-Identifier: GPL-2.0
/*
 * Acer WMI Gaming LED restricted off module.
 *
 * This production module intentionally does not expose a raw
 * GUID/method/input interface.  The only accepted proc command is:
 *
 *   echo off > /proc/acer_wmi_tester
 *
 * It replays the fixed WMID_GUID4 portion of the old broad script:
 *   - methods 1..13 with inputs 0, 1, 3, 5
 *   - methods 7..13 with the old second-pass fixed inputs
 *
 * Fan methods 14..19, misc methods 22..23, BIOS/Utility GUIDs, and arbitrary
 * GUID/method/input calls are not reachable through this interface.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/acpi.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/wmi.h>

#define MODULE_NAME "acer_wmi_tester"
#define INTERFACE_VERSION "led-off-v6-confirmed"
#define PROC_READ_SIZE 32768
#define ACER_WMID_GUID4 "7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56"
#define LEGACY_STEP1(method) \
	{ method, 0x0 }, { method, 0x1 }, { method, 0x3 }, { method, 0x5 }
#define LEGACY_STEP2(method) \
	{ method, 0x10001 }, { method, 0x10003 }, { method, 0x10005 }, \
	{ method, 0x10100 }, { method, 0x30100 }, { method, 0x50100 }, \
	{ method, 0x101 }, { method, 0x301 }, { method, 0x501 }

struct acer_wmi_allowed_call {
	u32 method_id;
	u64 input;
};

static const struct acer_wmi_allowed_call allowed_off_calls[] = {
	LEGACY_STEP1(1),
	LEGACY_STEP1(2),
	LEGACY_STEP1(3),
	LEGACY_STEP1(4),
	LEGACY_STEP1(5),
	LEGACY_STEP1(6),
	LEGACY_STEP1(7),
	LEGACY_STEP1(8),
	LEGACY_STEP1(9),
	LEGACY_STEP1(10),
	LEGACY_STEP1(11),
	LEGACY_STEP1(12),
	LEGACY_STEP1(13),
	LEGACY_STEP2(7),
	LEGACY_STEP2(8),
	LEGACY_STEP2(9),
	LEGACY_STEP2(10),
	LEGACY_STEP2(11),
	LEGACY_STEP2(12),
	LEGACY_STEP2(13),
};

struct acer_wmi_call_result {
	u32 method_id;
	u64 input;
	u64 output;
	int output_type;
	int output_len;
	int acpi_status;
};

static struct proc_dir_entry *proc_entry;
static DEFINE_MUTEX(call_lock);
static struct acer_wmi_call_result last_results[ARRAY_SIZE(allowed_off_calls)];
static bool last_run_valid;
static int last_run_status;

static ssize_t proc_read(struct file *file, char __user *buf,
			 size_t count, loff_t *pos)
{
	char *tmp;
	size_t len = 0;
	size_t i;
	ssize_t ret;

	tmp = kzalloc(PROC_READ_SIZE, GFP_KERNEL);
	if (!tmp)
		return -ENOMEM;

	mutex_lock(&call_lock);

	len += scnprintf(tmp + len, PROC_READ_SIZE - len,
		"interface : restricted LED off\n"
		"version   : %s\n"
		"guid      : %s\n"
		"command   : echo off > /proc/%s\n"
		"allowed   : legacy WMID_GUID4 replay; methods 1..13 and 7..13 fixed inputs; fan/misc/other GUIDs excluded\n"
		"call_count: %zu\n"
		"last_run  : %s\n",
		INTERFACE_VERSION, ACER_WMID_GUID4, MODULE_NAME,
		ARRAY_SIZE(allowed_off_calls),
		last_run_valid ? (last_run_status == 0 ? "acpi_success_physical_unverified" : "acpi_partial_failure") : "never");

	for (i = 0; i < ARRAY_SIZE(last_results); i++) {
		const struct acer_wmi_call_result *result = &last_results[i];

		len += scnprintf(tmp + len, PROC_READ_SIZE - len,
			"call[%zu]  : method=%u input=0x%llx status=%s(%d) output=0x%llx out_type=%d out_len=%d\n",
			i, result->method_id, result->input,
			result->acpi_status == 0 ? "SUCCESS" : "FAILURE",
			result->acpi_status, result->output,
			result->output_type, result->output_len);
	}

	mutex_unlock(&call_lock);

	ret = simple_read_from_buffer(buf, count, pos, tmp, len);
	kfree(tmp);
	return ret;
}

static void capture_wmi_output(struct acpi_buffer *output_buf,
			       struct acer_wmi_call_result *result)
{
	union acpi_object *obj;

	if (!output_buf->pointer)
		return;

	obj = output_buf->pointer;
	result->output_type = obj->type;

	if (obj->type == ACPI_TYPE_INTEGER) {
		result->output = obj->integer.value;
		result->output_len = sizeof(result->output);
	} else if (obj->type == ACPI_TYPE_BUFFER) {
		size_t copy_len = min_t(size_t, obj->buffer.length,
					sizeof(result->output));

		result->output_len = obj->buffer.length;
		memcpy(&result->output, obj->buffer.pointer, copy_len);
	}

	kfree(output_buf->pointer);
}

static int call_led_off_input(const struct acer_wmi_allowed_call *call,
			      struct acer_wmi_call_result *result)
{
	acpi_status status;
	u64 input = call->input;
	struct acpi_buffer input_buf = { sizeof(input), &input };
	struct acpi_buffer output_buf = { ACPI_ALLOCATE_BUFFER, NULL };

	memset(result, 0, sizeof(*result));
	result->method_id = call->method_id;
	result->input = input;

	status = wmi_evaluate_method(ACER_WMID_GUID4, 0, call->method_id,
				     &input_buf, &output_buf);
	if (ACPI_FAILURE(status)) {
		result->acpi_status = -(int)status;
		pr_warn(MODULE_NAME ": LED off method=%u input=0x%llx failed, ACPI status=0x%x\n",
			call->method_id, input, status);
		return -EIO;
	}

	result->acpi_status = 0;
	capture_wmi_output(&output_buf, result);
	pr_info(MODULE_NAME ": LED off method=%u input=0x%llx output=0x%llx\n",
		call->method_id, input, result->output);
	return 0;
}

static ssize_t proc_write(struct file *file, const char __user *buf,
			  size_t count, loff_t *pos)
{
	char kbuf[16] = {0};
	char *cmd;
	size_t i;
	int ret = 0;

	if (count >= sizeof(kbuf))
		return -EINVAL;

	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;

	cmd = strim(kbuf);
	if (strcmp(cmd, "off") != 0) {
		pr_err(MODULE_NAME ": unsupported command; write \"off\" only\n");
		return -EINVAL;
	}

	if (!wmi_has_guid(ACER_WMID_GUID4)) {
		pr_warn(MODULE_NAME ": WMID_GUID4 %s not found\n", ACER_WMID_GUID4);
		return -ENODEV;
	}

	mutex_lock(&call_lock);
	last_run_valid = false;
	last_run_status = 0;

	for (i = 0; i < ARRAY_SIZE(allowed_off_calls); i++) {
		memset(&last_results[i], 0, sizeof(last_results[i]));
		last_results[i].method_id = allowed_off_calls[i].method_id;
		last_results[i].input = allowed_off_calls[i].input;
	}

	for (i = 0; i < ARRAY_SIZE(allowed_off_calls); i++) {
		int call_ret;

		call_ret = call_led_off_input(&allowed_off_calls[i], &last_results[i]);
		if (call_ret && !ret)
			ret = call_ret;
	}

	last_run_status = ret;
	last_run_valid = true;
	mutex_unlock(&call_lock);

	return count;
}

static const struct proc_ops proc_fops = {
	.proc_read  = proc_read,
	.proc_write = proc_write,
};

static int __init acer_wmi_tester_init(void)
{
	size_t i;

	for (i = 0; i < ARRAY_SIZE(allowed_off_calls); i++) {
		last_results[i].method_id = allowed_off_calls[i].method_id;
		last_results[i].input = allowed_off_calls[i].input;
	}

	pr_info(MODULE_NAME ": restricted LED off interface for WMID_GUID4 %s (%s)\n",
		ACER_WMID_GUID4,
		wmi_has_guid(ACER_WMID_GUID4) ? "found" : "NOT found");

	proc_entry = proc_create(MODULE_NAME, 0600, NULL, &proc_fops);
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
MODULE_DESCRIPTION("Acer WMI restricted LED off helper");
