@import Foundation;

#include "i2c.h"
#include "utils.h"

static int getBytesUsed(UInt8* data) {
    // The checksum can be zero and still belongs to the packet.
    return (data[0] & 0x7f) + 2;
}

// Function to get ready for DDC operations for a specific display attribute
DDCPacket createDDCPacket(UInt8 attrCode) {
    DDCPacket packet = {};
    packet.data[2] = attrCode;
    packet.inputAddr = packet.data[2] == INPUT_ALT ? ALTERNATE_INPUT_ADDRESS : DEFAULT_INPUT_ADDRESS;
    return packet;
}

// Prepare DDC packet for read
void prepareDDCRead(DDCPacket *packet) {
    UInt8* data = packet->data;
    data[0] = 0x82;
    data[1] = 0x01;
    data[3] = 0x6E ^ packet->inputAddr ^ data[0] ^ data[1] ^ data[2];
}

// Prepare DDC packet for write
void prepareDDCWrite(DDCPacket *packet, UInt16 newValue) {
    UInt8* data = packet->data;
    data[0] = 0x84;
    data[1] = 0x03;
    data[3] = (newValue) >> 8;
    data[4] = newValue & 255;
    data[5] = 0x6E ^ packet->inputAddr ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
}


IOReturn performDDCReadAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    memset(packet->data, 0, sizeof(UInt8) * DDC_BUFFER_SIZE);
    usleep(DDC_READ_WAIT);
    return IOAVServiceReadI2C(avService, chipAddress, packet->inputAddr, packet->data, 12);
}

IOReturn performDDCWriteAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    IOReturn ret;

    for (int i = 0; i < DDC_ITERATIONS; ++i) {
        usleep(DDC_WAIT);
        if ((ret = IOAVServiceWriteI2C(avService, chipAddress, packet->inputAddr, packet->data, getBytesUsed(packet->data)))) {
            return ret;
        }
    }
    return ret;
}

IOReturn performDDCRead(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCReadAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}

IOReturn performDDCWrite(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCWriteAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}


DDCValue convertI2CtoDDC(char *i2cBytes) {
    const uint8_t *bytes = (const uint8_t *)i2cBytes;
    DDCValue invalid = {-1, -1};
    uint8_t checksum = 0x50;
    for (int i = 0; i < 11; i++) checksum ^= bytes[i];
    if (bytes[0] != 0x6e || bytes[1] != 0x88 || bytes[2] != 0x02 ||
        bytes[3] != 0 || checksum != 0) return invalid;
    // Decode two-byte values directly; sizeof(2) would copy four bytes.
    DDCValue value = {(bytes[8] << 8) | bytes[9], (bytes[6] << 8) | bytes[7]};
    return value;
}
