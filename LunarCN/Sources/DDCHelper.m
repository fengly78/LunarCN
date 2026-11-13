@import Foundation;
@import IOKit;
#include "i2c.h"
#include <assert.h>

static int fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    return 1;
}

static bool number(const char *text, unsigned long maximum, unsigned long *value) {
    if (!text || !*text || *text == '-') return false;
    char *end;
    errno = 0;
    *value = strtoul(text, &end, 10);
    return errno == 0 && *end == '\0' && *value <= maximum;
}

static DDCValue readValueOnce(DDCTransport transport, UInt8 control) {
    DDCPacket request = createDDCPacket(control);
    prepareDDCRead(&request);
    DDCValue invalid = {-1, -1};
    if (performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &request)) return invalid;
    DDCPacket reply = {};
    reply.inputAddr = request.inputAddr;
    if (performDDCReadAtChipAddress(transport.service, transport.chipAddress, &reply)) return invalid;
    if (reply.data[4] != control) return invalid;
    return convertI2CtoDDC((char *)reply.data);
}

static bool validValue(UInt8 control, DDCValue value) {
    if (value.curValue < 0 || value.maxValue < 0) return false;
    if (control == MUTE) return value.curValue == 1 || value.curValue == 2;
    return value.maxValue > 0 && value.curValue <= value.maxValue;
}

static DDCValue readValue(DDCTransport transport, UInt8 control) {
    DDCValue value = {-1, -1};
    for (int attempt = 0; attempt < 3; attempt++) {
        value = readValueOnce(transport, control);
        if (validValue(control, value)) break;
        if (attempt < 2) usleep(100000);
    }
    return value;
}

static bool validWrite(UInt8 control, unsigned long requested, DDCValue value) {
    if (control == MUTE) return requested == 1 || requested == 2;
    return requested <= (unsigned long)value.maxValue;
}

static int selfTest(void) {
    unsigned long parsed;
    assert(number("65535", 65535, &parsed) && parsed == 65535);
    assert(!number("-1", 65535, &parsed));
    assert(!number("65536", 65535, &parsed));
    assert(!number("20abc", 65535, &parsed));
    assert(validValue(VOLUME, (DDCValue){50, 100}));
    assert(!validValue(VOLUME, (DDCValue){101, 100}));
    assert(!validValue(VOLUME, (DDCValue){0, 0}));
    assert(validValue(MUTE, (DDCValue){1, 0}));
    assert(validValue(MUTE, (DDCValue){2, 0}));
    assert(!validValue(MUTE, (DDCValue){0, 0}));
    assert(validWrite(MUTE, 2, (DDCValue){1, 0}));
    assert(!validWrite(MUTE, 3, (DDCValue){1, 0}));
    assert(!validWrite(VOLUME, 101, (DDCValue){50, 100}));
    char reply[12] = {0x6e, (char)0x88, 0x02, 0, 0x10, 0, 0x01, 0x2c, 0, 0x80, 0, 0};
    uint8_t checksum = 0x50;
    for (int i = 0; i < 10; i++) checksum ^= (uint8_t)reply[i];
    reply[10] = (char)checksum;
    DDCValue value = convertI2CtoDDC(reply);
    assert(value.maxValue == 300 && value.curValue == 128);
    reply[10] ^= 1;
    assert(convertI2CtoDDC(reply).curValue == -1);
    memset(reply, 0, sizeof(reply));
    assert(convertI2CtoDDC(reply).curValue == -1);
    DDCPacket packet = createDDCPacket(LUMINANCE);
    prepareDDCWrite(&packet, 168);
    assert(packet.data[0] == 0x84 && packet.data[4] == 168 && packet.data[5] == 0);
    puts("DDC protocol self-test passed");
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return selfTest();
        bool setting = argc == 6 && strcmp(argv[1], "set") == 0;
        if (!(argc == 5 && strcmp(argv[1], "read") == 0) && !setting)
            return fail("参数无效。");
        unsigned long displayID, control, requested = 0;
        if (!number(argv[2], UINT32_MAX, &displayID) ||
            !number(argv[4], UINT8_MAX, &control) ||
            (control != LUMINANCE && control != CONTRAST && control != VOLUME && control != MUTE) ||
            (setting && !number(argv[5], UINT16_MAX, &requested))) return fail("数值超出范围。");

        DisplayInfos displays[MAX_DISPLAYS] = {};
        CGDisplayCount count = getOnlineDisplayInfos(displays);
        DDCTransport transport = {NULL, DDC_CHIP_ADDRESS_DEFAULT};
        for (CGDisplayCount i = 0; i < count; i++) {
            if (displays[i].id == displayID &&
                [displays[i].uuid isEqualToString:[NSString stringWithUTF8String:argv[3]]] &&
                !CGDisplayIsBuiltin(displays[i].id)) {
                transport = getDisplayDDCTransport(&displays[i]);
                break;
            }
        }
        if (!transport.service) return fail("未找到可用的显示器控制通道，请检查连接线或扩展坞。");
        DDCValue value = readValue(transport, (UInt8)control);
        if (!validValue((UInt8)control, value)) return fail("显示器未返回有效数据，可能不支持此功能，请检查 DDC/CI 设置。");
        if (setting) {
            if (!validWrite((UInt8)control, requested, value)) return fail("设置值不在显示器允许的范围内。");
            DDCPacket packet = createDDCPacket((UInt8)control);
            prepareDDCWrite(&packet, (UInt16)requested);
            if (performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &packet))
                return fail("写入失败，请检查显示器连接。");
            for (int attempt = 0; attempt < 3; attempt++) {
                usleep(100000);
                value = readValue(transport, (UInt8)control);
                if (value.curValue == (int)requested) break;
            }
            if (value.curValue != (int)requested) {
                fprintf(stderr, "显示器未确认目标值（目标 %lu，返回 %d）。请检查显示器设置或连接后重试。\n", requested, value.curValue);
                return 2;
            }
        }
        CFRelease(transport.service);
        printf("{\"current\":%d,\"maximum\":%d}\n", value.curValue, value.maxValue);
        return 0;
    }
}
