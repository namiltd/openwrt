// SPDX-License-Identifier: GPL-2.0-only

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <mtd/mtd-user.h>

#define ARRAY_SIZE(array)		(sizeof(array) / sizeof((array)[0]))

#define MIBIB_ERASESIZE			0x20000U
#define MIBIB_MIN_SIZE			0x80000U
#define MIBIB_HEADER_MAGIC1		0xfe569facU
#define MIBIB_HEADER_MAGIC2		0xcd7f127aU
#define MIBIB_HEADER_VERSION		4U
#define MIBIB_PTABLE_OFFSET		0x800U
#define MIBIB_PTABLE_MAGIC1		0x55ee73aaU
#define MIBIB_PTABLE_MAGIC2		0xe35ebddbU
#define MIBIB_PTABLE_VERSION		4U
#define MIBIB_PTABLE_MAX_PARTS		48U
#define MIBIB_PTABLE_HEADER_SIZE	16U
#define MIBIB_PENTRY_SIZE		28U
#define MIBIB_PENTRY_NAME_SIZE		16U
#define MIBIB_CRC_LENGTH		0x1800U
#define MIBIB_TRAILER_OFFSET		0x1800U
#define MIBIB_TRAILER_MAGIC1		0x9d41bea1U
#define MIBIB_TRAILER_MAGIC2		0xf1ded2eaU
#define MIBIB_TRAILER_VERSION		1U
#define MIBIB_TRAILER_CRC_OFFSET	0x180cU
#define MIBIB_BOOT_COPY_COUNT		2U

#define MR80X_PART_COUNT		16U
#define MR80X_ROOTFS_INDEX		11U
#define MR80X_ROOTFS_1_INDEX		12U
#define MR80X_TP_DATA_INDEX		13U
#define MR80X_RADIO_INDEX		14U
#define MR80X_DATA_INDEX		15U
#define MR80X_ROOTFS_OFFSET		0x32U
#define MR80X_ROOTFS_SLOT_LENGTH	0x150U
#define MR80X_ROOTFS_FULL_LENGTH	0x2a0U
#define MR80X_ROOTFS_1_OFFSET		0x182U
#define MR80X_TP_DATA_OFFSET		0x2d2U
#define MR80X_TP_DATA_LENGTH		0x42U
#define MR80X_RADIO_OFFSET		0x314U
#define MR80X_RADIO_LENGTH		0x22U
#define MR80X_DATA_OFFSET		0x336U
#define MR80X_DATA_LENGTH		0x4U

enum mr80x_profile {
	MR80X_PROFILE_UNKNOWN,
	MR80X_PROFILE_STOCK,
	MR80X_PROFILE_UNIFIED,
};

struct mibib_image {
	uint8_t *data;
	size_t size;
	size_t erasesize;
	size_t blocks;
	bool is_mtd;
	struct mtd_info_user mtd;
};

struct valid_copy {
	size_t block;
	uint32_t age;
	enum mr80x_profile profile;
};

static uint32_t get_le32(const uint8_t *p)
{
	return (uint32_t)p[0] |
	       ((uint32_t)p[1] << 8) |
	       ((uint32_t)p[2] << 16) |
	       ((uint32_t)p[3] << 24);
}

static void put_le32(uint8_t *p, uint32_t value)
{
	p[0] = value;
	p[1] = value >> 8;
	p[2] = value >> 16;
	p[3] = value >> 24;
}

/* Qualcomm stores a non-reflected CRC-32 with an all-zero initial value. */
static uint32_t mibib_crc32(const uint8_t *data, size_t length)
{
	uint32_t crc = 0;
	size_t i;
	unsigned int bit;

	for (i = 0; i < length; i++) {
		crc ^= (uint32_t)data[i] << 24;
		for (bit = 0; bit < 8; bit++)
			crc = crc & 0x80000000U ?
			      (crc << 1) ^ 0x04c11db7U : crc << 1;
	}

	return crc;
}

static uint8_t *ptable_entry(uint8_t *block, unsigned int index)
{
	return block + MIBIB_PTABLE_OFFSET + MIBIB_PTABLE_HEADER_SIZE +
	       index * MIBIB_PENTRY_SIZE;
}

static bool entry_name_is(const uint8_t *entry, const char *name)
{
	size_t length = strlen(name);

	return length < MIBIB_PENTRY_NAME_SIZE &&
	       !memcmp(entry, name, length) && entry[length] == '\0';
}

static bool entry_is_empty(const uint8_t *entry)
{
	unsigned int i;

	for (i = 0; i < MIBIB_PENTRY_SIZE; i++)
		if (entry[i] != 0)
			return false;

	return true;
}

static uint32_t entry_offset(const uint8_t *entry)
{
	return get_le32(entry + MIBIB_PENTRY_NAME_SIZE);
}

static uint32_t entry_length(const uint8_t *entry)
{
	return get_le32(entry + MIBIB_PENTRY_NAME_SIZE + sizeof(uint32_t));
}

static bool entry_matches(const uint8_t *entry, const char *name,
			  uint32_t offset, uint32_t length)
{
	return entry_name_is(entry, name) &&
	       entry_offset(entry) == offset &&
	       entry_length(entry) == length;
}

static enum mr80x_profile identify_mr80x_profile(uint8_t *block)
{
	uint8_t *rootfs = ptable_entry(block, MR80X_ROOTFS_INDEX);
	uint8_t *rootfs_1 = ptable_entry(block, MR80X_ROOTFS_1_INDEX);
	uint8_t *tp_data = ptable_entry(block, MR80X_TP_DATA_INDEX);
	uint8_t *radio = ptable_entry(block, MR80X_RADIO_INDEX);
	uint8_t *data = ptable_entry(block, MR80X_DATA_INDEX);
	uint8_t *ptable = block + MIBIB_PTABLE_OFFSET;

	if (get_le32(ptable + 12) != MR80X_PART_COUNT ||
	    !entry_matches(ptable_entry(block, 0), "0:SBL1", 0x0, 0x4) ||
	    !entry_matches(ptable_entry(block, 1), "0:MIBIB", 0x4, 0x4) ||
	    !entry_matches(ptable_entry(block, 2), "0:BOOTCONFIG", 0x8, 0x2) ||
	    !entry_matches(ptable_entry(block, 3), "0:BOOTCONFIG1", 0xa, 0x2) ||
	    !entry_matches(ptable_entry(block, 4), "0:QSEE", 0xc, 0x8) ||
	    !entry_matches(ptable_entry(block, 5), "0:DEVCFG", 0x14, 0x2) ||
	    !entry_matches(ptable_entry(block, 6), "0:CDT", 0x16, 0x2) ||
	    !entry_matches(ptable_entry(block, 7), "0:APPSBLENV", 0x18, 0x4) ||
	    !entry_matches(ptable_entry(block, 8), "0:APPSBL", 0x1c, 0xa) ||
	    !entry_matches(ptable_entry(block, 9), "0:ART", 0x26, 0x8) ||
	    !entry_matches(ptable_entry(block, 10), "0:TRAINING", 0x2e, 0x4) ||
	    !entry_matches(tp_data, "tp_data", MR80X_TP_DATA_OFFSET,
			   MR80X_TP_DATA_LENGTH) ||
	    !entry_matches(radio, "radio", MR80X_RADIO_OFFSET,
			   MR80X_RADIO_LENGTH) ||
	    !entry_matches(data, "data", MR80X_DATA_OFFSET,
			   MR80X_DATA_LENGTH))
		return MR80X_PROFILE_UNKNOWN;

	if (entry_matches(rootfs, "rootfs", MR80X_ROOTFS_OFFSET,
			  MR80X_ROOTFS_SLOT_LENGTH) &&
	    entry_matches(rootfs_1, "rootfs_1", MR80X_ROOTFS_1_OFFSET,
			  MR80X_ROOTFS_SLOT_LENGTH))
		return MR80X_PROFILE_STOCK;

	if (entry_matches(rootfs, "rootfs", MR80X_ROOTFS_OFFSET,
			  MR80X_ROOTFS_FULL_LENGTH) &&
	    entry_is_empty(rootfs_1))
		return MR80X_PROFILE_UNIFIED;

	return MR80X_PROFILE_UNKNOWN;
}

static const char *profile_name(enum mr80x_profile profile)
{
	switch (profile) {
	case MR80X_PROFILE_STOCK:
		return "mr80x-stock";
	case MR80X_PROFILE_UNIFIED:
		return "mr80x-unified";
	default:
		return "unknown";
	}
}

static enum mr80x_profile parse_profile(const char *name)
{
	if (!strcmp(name, "mr80x-stock"))
		return MR80X_PROFILE_STOCK;
	if (!strcmp(name, "mr80x-unified"))
		return MR80X_PROFILE_UNIFIED;

	return MR80X_PROFILE_UNKNOWN;
}

static bool block_is_erased(const uint8_t *block, size_t length)
{
	size_t i;

	for (i = 0; i < length; i++)
		if (block[i] != 0xff)
			return false;

	return true;
}

static bool copy_is_valid(uint8_t *block, enum mr80x_profile *profile,
			  uint32_t *age)
{
	uint8_t *ptable = block + MIBIB_PTABLE_OFFSET;
	uint8_t *trailer = block + MIBIB_TRAILER_OFFSET;
	uint32_t numparts;

	if (get_le32(block) != MIBIB_HEADER_MAGIC1 ||
	    get_le32(block + 4) != MIBIB_HEADER_MAGIC2 ||
	    get_le32(block + 8) != MIBIB_HEADER_VERSION ||
	    get_le32(ptable) != MIBIB_PTABLE_MAGIC1 ||
	    get_le32(ptable + 4) != MIBIB_PTABLE_MAGIC2 ||
	    get_le32(ptable + 8) != MIBIB_PTABLE_VERSION ||
	    get_le32(trailer) != MIBIB_TRAILER_MAGIC1 ||
	    get_le32(trailer + 4) != MIBIB_TRAILER_MAGIC2 ||
	    get_le32(trailer + 8) != MIBIB_TRAILER_VERSION ||
	    get_le32(trailer + 12) != mibib_crc32(block, MIBIB_CRC_LENGTH))
		return false;

	numparts = get_le32(ptable + 12);
	if (!numparts || numparts > MIBIB_PTABLE_MAX_PARTS)
		return false;

	*age = get_le32(block + 12);
	*profile = identify_mr80x_profile(block);
	return true;
}

static ssize_t read_full_at(int fd, void *buffer, size_t length, off_t offset)
{
	uint8_t *p = buffer;
	size_t done = 0;

	while (done < length) {
		ssize_t ret = pread(fd, p + done, length - done, offset + done);

		if (ret < 0 && errno == EINTR)
			continue;
		if (ret <= 0)
			return -1;
		done += ret;
	}

	return done;
}

static ssize_t write_full_at(int fd, const void *buffer, size_t length,
			     off_t offset)
{
	const uint8_t *p = buffer;
	size_t done = 0;

	while (done < length) {
		ssize_t ret = pwrite(fd, p + done, length - done, offset + done);

		if (ret < 0 && errno == EINTR)
			continue;
		if (ret <= 0)
			return -1;
		done += ret;
	}

	return done;
}

static int load_image(const char *path, bool writable, struct mibib_image *image,
		      int *fd_out)
{
	struct stat st;
	int flags = writable ? O_RDWR | O_SYNC : O_RDONLY;
	int fd;

	memset(image, 0, sizeof(*image));
	fd = open(path, flags);
	if (fd < 0) {
		fprintf(stderr, "qcom-mibib: cannot open %s: %s\n",
			path, strerror(errno));
		return -1;
	}

	if (fstat(fd, &st)) {
		fprintf(stderr, "qcom-mibib: cannot stat %s: %s\n",
			path, strerror(errno));
		close(fd);
		return -1;
	}

	if (S_ISCHR(st.st_mode) && !ioctl(fd, MEMGETINFO, &image->mtd)) {
		image->is_mtd = true;
		image->size = image->mtd.size;
		image->erasesize = image->mtd.erasesize;
		if (image->mtd.type != MTD_NANDFLASH &&
		    image->mtd.type != MTD_MLCNANDFLASH) {
			fprintf(stderr, "qcom-mibib: %s is not a NAND MTD\n", path);
			close(fd);
			return -1;
		}
	} else if (S_ISREG(st.st_mode)) {
		image->size = st.st_size;
		image->erasesize = MIBIB_ERASESIZE;
	} else {
		fprintf(stderr, "qcom-mibib: %s is not a regular file or MTD\n",
			path);
		close(fd);
		return -1;
	}

	if (image->size < MIBIB_MIN_SIZE ||
	    image->erasesize != MIBIB_ERASESIZE ||
	    image->size % image->erasesize) {
		fprintf(stderr,
			"qcom-mibib: unsupported geometry size=%zu erase=%zu\n",
			image->size, image->erasesize);
		close(fd);
		return -1;
	}

	image->data = malloc(image->size);
	if (!image->data) {
		fprintf(stderr, "qcom-mibib: out of memory\n");
		close(fd);
		return -1;
	}

	if (read_full_at(fd, image->data, image->size, 0) < 0) {
		fprintf(stderr, "qcom-mibib: cannot read %s: %s\n",
			path, strerror(errno));
		free(image->data);
		close(fd);
		return -1;
	}

	image->blocks = image->size / image->erasesize;
	*fd_out = fd;
	return 0;
}

static size_t collect_valid_copies(struct mibib_image *image,
				   struct valid_copy *copies, size_t max)
{
	size_t count = 0;
	size_t i;

	for (i = 0; i < image->blocks; i++) {
		uint8_t *block = image->data + i * image->erasesize;
		enum mr80x_profile profile;
		uint32_t age;

		if (!copy_is_valid(block, &profile, &age))
			continue;
		if (count < max) {
			copies[count].block = i;
			copies[count].age = age;
			copies[count].profile = profile;
		}
		count++;
	}

	return count;
}

static int newest_copy(const struct valid_copy *copies, size_t count)
{
	size_t i;
	size_t newest = 0;

	if (!count)
		return -1;

	for (i = 1; i < count; i++)
		if (copies[i].age > copies[newest].age)
			newest = i;

	return newest;
}

static bool mtd_block_is_bad(int fd, size_t offset)
{
	int64_t address = offset;
	int ret = ioctl(fd, MEMGETBADBLOCK, &address);

	if (ret < 0) {
		fprintf(stderr, "qcom-mibib: MEMGETBADBLOCK failed: %s\n",
			strerror(errno));
		return true;
	}

	return ret > 0;
}

static int prepare_profile(struct mibib_image *image, int fd,
			   enum mr80x_profile target, uint8_t **new_block_out,
			   int *target_block_out)
{
	struct valid_copy boot_copies[MIBIB_BOOT_COPY_COUNT];
	struct valid_copy all_copies[32];
	uint8_t *source;
	uint8_t *new_block;
	uint8_t *rootfs;
	uint8_t *rootfs_1;
	size_t all_count;
	uint32_t max_age = 0;
	int newest;
	int target_block;
	size_t i;

	if (image->size != MIBIB_MIN_SIZE || image->blocks != 4) {
		fprintf(stderr,
			"qcom-mibib: MR80X profile requires an exact 512 KiB MIBIB\n");
		return -1;
	}

	for (i = 0; i < MIBIB_BOOT_COPY_COUNT; i++) {
		uint8_t *block = image->data + i * image->erasesize;

		boot_copies[i].block = i;
		if (!copy_is_valid(block, &boot_copies[i].profile,
				   &boot_copies[i].age) ||
		    boot_copies[i].profile == MR80X_PROFILE_UNKNOWN) {
			fprintf(stderr,
				"qcom-mibib: boot slot %zu is not a valid known copy\n",
				i);
			return -1;
		}
		if (image->is_mtd &&
		    mtd_block_is_bad(fd, i * image->erasesize)) {
			fprintf(stderr,
				"qcom-mibib: boot slot %zu is marked bad\n", i);
			return -1;
		}
	}

	newest = newest_copy(boot_copies, ARRAY_SIZE(boot_copies));
	if (boot_copies[newest].profile == target) {
		printf("qcom-mibib: active boot copy already uses %s\n",
		       profile_name(target));
		*new_block_out = NULL;
		*target_block_out = -1;
		return 0;
	}

	all_count = collect_valid_copies(image, all_copies,
					 ARRAY_SIZE(all_copies));
	if (!all_count || all_count > ARRAY_SIZE(all_copies)) {
		fprintf(stderr, "qcom-mibib: no usable set of valid copies\n");
		return -1;
	}
	for (i = 0; i < all_count; i++)
		if (all_copies[i].age > max_age)
			max_age = all_copies[i].age;
	if (max_age == UINT32_MAX) {
		fprintf(stderr, "qcom-mibib: copy age cannot be incremented\n");
		return -1;
	}

	/*
	 * The MR80X bootloader only scans eraseblocks 0 and 1 (shared
	 * u-boot-2016 codebase across the v2/v5 product family - see
	 * MIBIB_BOOT_COPY_COUNT). Keep the active copy intact and replace
	 * the older boot slot atomically.
	 */
	target_block = newest == 0 ? 1 : 0;

	source = image->data +
		 boot_copies[newest].block * image->erasesize;
	new_block = malloc(image->erasesize);
	if (!new_block) {
		fprintf(stderr, "qcom-mibib: out of memory\n");
		return -1;
	}
	memcpy(new_block, source, image->erasesize);

	put_le32(new_block + 12, max_age + 1);
	rootfs = ptable_entry(new_block, MR80X_ROOTFS_INDEX);
	rootfs_1 = ptable_entry(new_block, MR80X_ROOTFS_1_INDEX);

	if (target == MR80X_PROFILE_UNIFIED) {
		put_le32(rootfs + MIBIB_PENTRY_NAME_SIZE + sizeof(uint32_t),
			 MR80X_ROOTFS_FULL_LENGTH);
		memset(rootfs_1, 0, MIBIB_PENTRY_SIZE);
	} else {
		put_le32(rootfs + MIBIB_PENTRY_NAME_SIZE + sizeof(uint32_t),
			 MR80X_ROOTFS_SLOT_LENGTH);
		memset(rootfs_1, 0, MIBIB_PENTRY_SIZE);
		memcpy(rootfs_1, "rootfs_1", sizeof("rootfs_1"));
		put_le32(rootfs_1 + MIBIB_PENTRY_NAME_SIZE,
			 MR80X_ROOTFS_1_OFFSET);
		put_le32(rootfs_1 + MIBIB_PENTRY_NAME_SIZE + sizeof(uint32_t),
			 MR80X_ROOTFS_SLOT_LENGTH);
		put_le32(rootfs_1 + MIBIB_PENTRY_NAME_SIZE +
			 2 * sizeof(uint32_t), 0xffffU);
	}

	put_le32(new_block + MIBIB_TRAILER_CRC_OFFSET,
		 mibib_crc32(new_block, MIBIB_CRC_LENGTH));

	{
		enum mr80x_profile generated_profile;
		uint32_t generated_age;

		if (!copy_is_valid(new_block, &generated_profile,
				   &generated_age) ||
		    generated_profile != target ||
		    generated_age != max_age + 1) {
			fprintf(stderr,
				"qcom-mibib: internal validation of generated copy failed\n");
			free(new_block);
			return -1;
		}
	}

	printf("qcom-mibib: source block=%zu age=%u profile=%s\n",
	       boot_copies[newest].block, boot_copies[newest].age,
	       profile_name(boot_copies[newest].profile));
	printf("qcom-mibib: target block=%d age=%u profile=%s\n",
	       target_block, max_age + 1, profile_name(target));

	*new_block_out = new_block;
	*target_block_out = target_block;
	return 0;
}

static int inspect_image(struct mibib_image *image)
{
	struct valid_copy copies[32];
	struct valid_copy boot_copies[MIBIB_BOOT_COPY_COUNT];
	size_t count;
	size_t boot_count = 0;
	size_t i;
	int newest;

	count = collect_valid_copies(image, copies,
				     ARRAY_SIZE(copies));
	if (count > ARRAY_SIZE(copies)) {
		fprintf(stderr, "qcom-mibib: too many valid copies\n");
		return -1;
	}
	printf("geometry: size=0x%zx erase=0x%zx blocks=%zu\n",
	       image->size, image->erasesize, image->blocks);

	for (i = 0; i < image->blocks; i++) {
		uint8_t *block = image->data + i * image->erasesize;
		size_t j;
		bool found = false;

		for (j = 0; j < count; j++) {
			if (copies[j].block != i)
				continue;
			printf("block %zu: valid age=%u profile=%s\n", i,
			       copies[j].age, profile_name(copies[j].profile));
			found = true;
			break;
		}
		if (!found)
			printf("block %zu: %s\n", i,
			       block_is_erased(block, image->erasesize) ?
			       "erased" : "invalid/non-empty");
	}

	for (i = 0; i < count; i++)
		if (copies[i].block < MIBIB_BOOT_COPY_COUNT)
			boot_copies[boot_count++] = copies[i];

	newest = newest_copy(boot_copies, boot_count);
	if (newest < 0) {
		fprintf(stderr, "qcom-mibib: no valid boot copies found\n");
		return -1;
	}

	printf("active boot copy: block=%zu age=%u profile=%s\n",
	       boot_copies[newest].block, boot_copies[newest].age,
	       profile_name(boot_copies[newest].profile));
	return boot_copies[newest].profile == MR80X_PROFILE_UNKNOWN ? -1 : 0;
}

static int write_mtd_copy(int fd, struct mibib_image *image,
			  const uint8_t *new_block, int target_block,
			  enum mr80x_profile target)
{
	struct erase_info_user erase = {
		.start = target_block * image->erasesize,
		.length = image->erasesize,
	};
	uint8_t *verify;
	enum mr80x_profile profile;
	uint32_t age;

	if (ioctl(fd, MEMERASE, &erase)) {
		fprintf(stderr, "qcom-mibib: erase of block %d failed: %s\n",
			target_block, strerror(errno));
		return -1;
	}
	if (write_full_at(fd, new_block, image->erasesize, erase.start) < 0) {
		fprintf(stderr, "qcom-mibib: write of block %d failed: %s\n",
			target_block, strerror(errno));
		return -1;
	}
	if (fsync(fd) && errno != EINVAL && errno != ENOTSUP) {
		fprintf(stderr, "qcom-mibib: fsync failed: %s\n",
			strerror(errno));
		return -1;
	}

	verify = malloc(image->erasesize);
	if (!verify) {
		fprintf(stderr, "qcom-mibib: out of memory during verification\n");
		return -1;
	}
	if (read_full_at(fd, verify, image->erasesize, erase.start) < 0 ||
	    memcmp(verify, new_block, image->erasesize) ||
	    !copy_is_valid(verify, &profile, &age) || profile != target) {
		fprintf(stderr,
			"qcom-mibib: readback verification failed for block %d\n",
			target_block);
		free(verify);
		return -1;
	}
	free(verify);

	printf("qcom-mibib: block %d written and verified (age=%u)\n",
	       target_block, age);
	return 0;
}

static int create_image(const char *input, const char *output,
			enum mr80x_profile target)
{
	struct mibib_image image;
	uint8_t *new_block = NULL;
	int target_block;
	int input_fd;
	int output_fd = -1;
	int ret = -1;

	if (load_image(input, false, &image, &input_fd))
		return -1;
	if (prepare_profile(&image, input_fd, target, &new_block,
			    &target_block))
		goto out;
	if (!new_block) {
		fprintf(stderr, "qcom-mibib: no output created\n");
		goto out;
	}

	memcpy(image.data + target_block * image.erasesize, new_block,
	       image.erasesize);
	output_fd = open(output, O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (output_fd < 0) {
		fprintf(stderr, "qcom-mibib: cannot create %s: %s\n",
			output, strerror(errno));
		goto out;
	}
	if (write_full_at(output_fd, image.data, image.size, 0) < 0 ||
	    fsync(output_fd)) {
		fprintf(stderr, "qcom-mibib: cannot write %s: %s\n",
			output, strerror(errno));
		goto out;
	}

	printf("qcom-mibib: created %s; no flash device was modified\n", output);
	ret = 0;
out:
	if (output_fd >= 0)
		close(output_fd);
	free(new_block);
	free(image.data);
	close(input_fd);
	return ret;
}

static int apply_profile(const char *path, enum mr80x_profile target,
			 bool commit)
{
	struct mibib_image image;
	uint8_t *new_block = NULL;
	int target_block;
	int fd;
	int ret = -1;

	if (load_image(path, commit, &image, &fd))
		return -1;
	if (!image.is_mtd) {
		fprintf(stderr,
			"qcom-mibib: apply requires a NAND MTD character device\n");
		goto out;
	}
	if (prepare_profile(&image, fd, target, &new_block, &target_block))
		goto out;
	if (!new_block) {
		ret = 0;
		goto out;
	}
	if (!commit) {
		printf("qcom-mibib: probe successful; no data was written\n");
		ret = 0;
		goto out;
	}

	ret = write_mtd_copy(fd, &image, new_block, target_block, target);
out:
	free(new_block);
	free(image.data);
	close(fd);
	return ret;
}

static void usage(const char *program)
{
	fprintf(stderr,
		"Usage:\n"
		"  %s inspect <file-or-mtd>\n"
		"  %s create <input-file> <output-file> <profile>\n"
		"  %s probe <mtd-device> <profile>\n"
		"  %s apply <mtd-device> <profile> --yes-really\n"
		"\n"
		"Profiles: mr80x-stock, mr80x-unified\n",
		program, program, program, program);
}

int main(int argc, char **argv)
{
	struct mibib_image image;
	enum mr80x_profile profile;
	int fd;
	int ret;

	if (argc == 3 && !strcmp(argv[1], "inspect")) {
		if (load_image(argv[2], false, &image, &fd))
			return EXIT_FAILURE;
		ret = inspect_image(&image);
		free(image.data);
		close(fd);
		return ret ? EXIT_FAILURE : EXIT_SUCCESS;
	}

	if (argc == 5 && !strcmp(argv[1], "create")) {
		profile = parse_profile(argv[4]);
		if (profile == MR80X_PROFILE_UNKNOWN) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		return create_image(argv[2], argv[3], profile) ?
		       EXIT_FAILURE : EXIT_SUCCESS;
	}

	if (argc == 4 && !strcmp(argv[1], "probe")) {
		profile = parse_profile(argv[3]);
		if (profile == MR80X_PROFILE_UNKNOWN) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		return apply_profile(argv[2], profile, false) ?
		       EXIT_FAILURE : EXIT_SUCCESS;
	}

	if (argc == 5 && !strcmp(argv[1], "apply") &&
	    !strcmp(argv[4], "--yes-really")) {
		profile = parse_profile(argv[3]);
		if (profile == MR80X_PROFILE_UNKNOWN) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		return apply_profile(argv[2], profile, true) ?
		       EXIT_FAILURE : EXIT_SUCCESS;
	}

	usage(argv[0]);
	return EXIT_FAILURE;
}
