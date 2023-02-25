//
//  BleDelegates.swift
//  FocusControl
//
//  Created by Barry Bryant on 12/5/21
//  Base class sets iOS app as BLE Central to communicate with BLE Peripheral
//
//  Derive a model class from this class.  Then call:
//  1. bleInit - to initiate CBCentralManager and CBPeripheral Delegates
//  2. Optionally override any report...() methods to sync model state to any
//     state of delegate processing.
//  3. bleWrite - to write data to a Peripheral
//  4. bleRead - to initiate a noWait read from Peripheral.

import CoreBluetooth
import UIKit

protocol BleWizardDelegate: AnyObject {
  func reportBleScanning()
  func reportBleNotAvailable()
  func reportBleServiceFound()
  func reportBleServiceConnected()
  func reportBleServiceDisconnected()
  func reportBleServiceCharaceristicsScanned()
}

class BleWizard: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  
  weak var delegate: BleWizardDelegate?

  private var service_uuid: CBUUID     // UUID of desired service
  private var ble_data_uuids: [CBUUID]  // UUID for each BLE data value
 
  private var dataDictionary: [CBUUID: CBCharacteristic?] = [:] // uuid to characteristic mapping
  private var readResponderDictionary: [CBUUID: (Int32)->Void] = [:]

  // Core Bluetooth variables
  private var cbCentralManager       : CBCentralManager!
  private var focusMotorPeripheral   : CBPeripheral?

  init(serviceUUID: CBUUID, bleDataUUIDs: [CBUUID]) {
    self.service_uuid = serviceUUID
    self.ble_data_uuids = bleDataUUIDs
    super.init()
  }
  
  // Called by derived class to initialize BLE communication
  public func start() {
    cbCentralManager = CBCentralManager(delegate: self, queue: nil)
  }

//MARK:- CBCentralManagerDelegate

  // Step 1 - Start scanning for BLE DEVICE advertising required SERVICE
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn) {
      delegate?.reportBleScanning()
      central.scanForPeripherals(withServices: [service_uuid], options: nil)
    } else {
      delegate?.reportBleNotAvailable()
    }
  }

  // Step 2 - Once SERVICE found found, stop scanning and connect Peripheral
  func centralManager(_ central: CBCentralManager,
                      didDiscover peripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber)
  {
    cbCentralManager.stopScan()
    cbCentralManager.connect(peripheral, options: nil)
    focusMotorPeripheral = peripheral
    delegate?.reportBleServiceFound()
  }
  
  // Step 3 - Once connected to peripheral, Find desired service
  func centralManager(_ central: CBCentralManager,
                      didConnect peripheral: CBPeripheral)
  {
    peripheral.delegate = self
    peripheral.discoverServices([service_uuid]) // already know it has it!

    delegate?.reportBleServiceConnected()
  }
  
  // If disconnected - resume  scanning for Focus Motor peripheral
  func centralManager(_ central: CBCentralManager,
                      didDisconnectPeripheral peripheral: CBPeripheral,
                      error: Error?)
  {
    if let e = error {
      print("error not nil in centralManager.didDisconnectPeripheral")
      print(e.localizedDescription)
    }

    cbCentralManager.scanForPeripherals(withServices: [service_uuid],
                                        options: nil)

    delegate?.reportBleServiceDisconnected()
  }

//MARK:- CBPeripheralDelegate

  // Step 4 - Once service found, look for specific parameter characteristics
  func peripheral(_ peripheral: CBPeripheral,
                  didDiscoverServices error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didDiscoverServices")
      print(e.localizedDescription)
      return
    }

    if let services = peripheral.services {
      for service in services {
        peripheral.discoverCharacteristics(ble_data_uuids, for: service)
      }
    }
  }

  // Step 5 - Store CBCharacterstic values for future communication
  func peripheral(_ peripheral: CBPeripheral,
                  didDiscoverCharacteristicsFor service: CBService,
                  error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didDiscoverCharacteristicsFor")
      print(e.localizedDescription)
      return
    }

    // Create a dictionary to find characteristics, via UUID
    if let characteristic = service.characteristics {
      for characteristic in characteristic {
        dataDictionary[characteristic.uuid] = characteristic
      }
    }
    delegate?.reportBleServiceCharaceristicsScanned()
  }
  
//MARK:- Write(UUID) and Read(UUID) calls

  // Called by derived class to write single Int32 to BLE
  func bleWrite(_ write_uuid: CBUUID, writeData: Int32) {
    if let write_characteristic = dataDictionary[write_uuid] {
      let data = Data(bytes: [writeData], count: 4) // Int32 writeData is 4 bytes
      focusMotorPeripheral?.writeValue(data,
                                       for: write_characteristic!,
                                       type: .withoutResponse)
    }
  }
  
  // Called by derived class to write a FocusMsg struct to BLE
  func bleWrite(_ write_uuid: CBUUID, focusMsg: FocusMsg) {
    if let write_characteristic = dataDictionary[write_uuid] {
      let data = Data(bytes: [focusMsg], count: 8) // Int32 writeData is 4 bytes
      focusMotorPeripheral?.writeValue(data,
                                       for: write_characteristic!,
                                       type: .withoutResponse)
    }
  }
  
  
  enum BluetoothReadError: LocalizedError {
    case characteristicNotFound
  }
  
  func bleRead(uuid: CBUUID, onReadResult: @escaping (Int32)->Void) throws {
    guard let read_characteristic = dataDictionary[uuid] else {      // find characteristic
      throw BluetoothReadError.characteristicNotFound
    }
    focusMotorPeripheral?.readValue(for: read_characteristic!) // issue the read
    readResponderDictionary[uuid] = onReadResult              // handle data when read completes
  }

  // Called by peripheral.readValue,
  // or after updates if using peripheral.setNotifyValue
  func peripheral(_ peripheral: CBPeripheral,
                  didUpdateValueFor characteristic: CBCharacteristic,
                  error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didUpdateValueFor")
      print(e.localizedDescription)
      return
    }

    // assume all read values are Int32
    // - else require each responder to perform appropriate .getBytes mapping
    var readData:Int32 = 0
    // Copy Data buffer to Int32
    if let data = characteristic.value {
      (data as NSData).getBytes(&readData, length:4)
    }
    
    // call UUID's responder with the Int32 Data
    if let responder = readResponderDictionary[characteristic.uuid] {
      responder(readData)
    }
  }

}
