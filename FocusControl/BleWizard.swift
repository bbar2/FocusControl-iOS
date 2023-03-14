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

// This approach requires the wizard to be modified for each DataType to be bleRead.
// Haven't found a Generic approach (similer to func bleWrite<WriteType>) for bleRead
// 1. Add a private var readResponderReadType dictionary
// 2. Add bleRead(_ uuid: CBUUID, onReadResult: @escaping (ReadType)->Void) and/or
//    setNotify(_ notify_uuid: CBUUID, onReadResult: @escaping (ReadType)->Void)
// 3. Modify func peripheral(_ didUpdateValueFor) to call correct responder by UUID

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
 
  private var characteristicDictionary: [CBUUID: CBCharacteristic?] = [:] // uuid to characteristic mapping

  // need readResponder dictionary for each data type that will be read over ble
  private var readRespondersInt32: [CBUUID: (Int32)->Void] = [:]
  private var readResponderXlData: [CBUUID: (XlData)->Void] = [:]

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
  
  public func disconnect() {
    if let focusMotor = focusMotorPeripheral {
      delegate?.reportBleServiceDisconnected()
      cbCentralManager.cancelPeripheralConnection(focusMotor)
    }
  }
  
  public func reconnect() {
    delegate?.reportBleScanning()
    cbCentralManager.scanForPeripherals(withServices: [service_uuid], options: nil)
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
        characteristicDictionary[characteristic.uuid] = characteristic
      }
    }
    delegate?.reportBleServiceCharaceristicsScanned()
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
    
    // Select the read responder based on the UUID and readResponderType available
    if characteristic.uuid.uuidString.compare("828b0005-046a-42c7-9c16-00ca297e95eb",
                                              options: .caseInsensitive) == .orderedSame
    {
      var xlData = XlData(x: 0.0, y: 0.0, z: 0.0)

      // Copy Data buffer to XlDataStruct
      if let dataBytes = characteristic.value {
        (dataBytes as NSData).getBytes(&xlData,
                                       length: MemoryLayout<XlData>.size)
      }
      
      // call UUID's responder with the XlData structure
      if let responder = readResponderXlData[characteristic.uuid] {
        responder(xlData)
      }
    }
    else // all other read values are Int32
    {
      var readData:Int32 = 0
      // Copy Data buffer to Int32
      if let dataBytes = characteristic.value {
        (dataBytes as NSData).getBytes(&readData,
                                       length: MemoryLayout<Int32>.size)
      }
      
      // call UUID's responder with the Int32 data
      if let responder = readRespondersInt32[characteristic.uuid] {
        responder(readData)
      }
    }
  }

  //MARK:- bleWrite(UUID), bleRead(UUID) and setNotify(UUID) functions
  // Need a bleRead and bleNotify for each data type to be read over ble

  // Called by derived class to write single WriteType data item to BLE
  func bleWrite<WriteType>(_ write_uuid: CBUUID, writeData: WriteType) {
    if let write_characteristic = characteristicDictionary[write_uuid] {
      let data = Data(bytes: [writeData], count: MemoryLayout<WriteType>.size)
      focusMotorPeripheral?.writeValue(data,
                                       for: write_characteristic!,
                                       type: .withoutResponse)
    }
  }
  
  // THIS FAILED - couldn't assign (T)->Void closure to (Any)->Void responder [:]
  //               example error: Can't assign (Int32)->Void to ((Any)->Void)?
  //             - Alternatice is a bleRead for each readDataType
  //private var readResponder: [CBUUID: (Any)->Void] = [:] // above in class def
  //  func bleRead<T>(uuid: CBUUID, onReadResult: @escaping (T)->Void) {
  //    readResponder[uuid] = onReadResult  // handle data when read completes
  //    if let read_characteristic = dataDictionary[uuid] { // find characteristic
  //      focusMotorPeripheral?.readValue(for: read_characteristic!) // issue the read
  //    }
  //  }

  func bleRead(_ uuid: CBUUID,
               onReadResult: @escaping (Int32)->Void) {

    readRespondersInt32[uuid] = onReadResult  // handle data when read completes

    if let int32Characteristic = characteristicDictionary[uuid] { // find characteristic
      if let peripheral = focusMotorPeripheral {
        peripheral.readValue(for: int32Characteristic!) // issue the read
      }
    }
  }

  func bleRead(_ uuid: CBUUID,
               onReadResult: @escaping (XlData)->Void) {
    
    readResponderXlData[uuid] = onReadResult  // handle data when read completes

    if let xlDataCharacteristic = characteristicDictionary[uuid] { // find characteristic
      if let peripheral = focusMotorPeripheral {
        peripheral.readValue(for: xlDataCharacteristic!) // issue the read
      }
    }
  }

  func setNotify(_ uuid: CBUUID,
                 onReadResult: @escaping (XlData)->Void) {

    // Save closure to execute upon Notification (peripheral write complete)
    readResponderXlData[uuid] = onReadResult

    // Look up the Characteristic, and enable nofication
    if let notifyCharacteristic = characteristicDictionary[uuid] {
      if let peripheral = focusMotorPeripheral {
        peripheral.setNotifyValue(true, for: notifyCharacteristic!);
      }
    }
  }
  
}
