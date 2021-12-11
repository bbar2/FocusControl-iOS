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

class BleDelegates : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate{

  private var service_uuid: CBUUID!     // UUID of desired service
  private var ble_data_uuid: [CBUUID]!  // UUID for each BLE data value
 
  private var dataDictionary: [CBUUID: CBCharacteristic?] = [:] // uuid to characteristic mapping
  private var readResponderDictionary: [CBUUID: (Int32)->Void] = [:]

  // Core Bluetooth variables
  private var cbCentralManager       : CBCentralManager!
  private var focusMotorPeripheral   : CBPeripheral?

  // Called by derived class to initialize BLE communication
  func bleInit(service_uuid uuid:CBUUID, ble_data_uuid ble_data:[CBUUID]) {
    service_uuid = uuid
    ble_data_uuid = ble_data
    
    //  Starts the sequence of Steps in FocusMotorBle delegates
    cbCentralManager = CBCentralManager(delegate: self, queue: nil)
  }

//MARK:- CBCentralManagerDelegate

  // Step 1 - Start scanning for BLE DEVICE advertising required SERVICE
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn) {
      reportBleScanning()
      central.scanForPeripherals(withServices: [service_uuid],
                                 options: nil)
    } else {
      reportBleNotAvailable()
    }
  }
  
  func reportBleScanning(){
      print("override reportBleScanning() in derived class")
  }
  
  func reportBleNotAvailable(){
    print("override reportBleNotAvailable() in derived class")
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
    reportBleServiceFound()
  }
  
  func reportBleServiceFound(){
    print("override reportBleServiceConnected() in derived class")
  }
  
  // Step 3 - Once connected to peripheral, Find desired service
  func centralManager(_ central: CBCentralManager,
                      didConnect peripheral: CBPeripheral)
  {
    peripheral.delegate = self
    peripheral.discoverServices([service_uuid]) // already know it has it!

    reportBleServiceConnected()
  }
  
  func reportBleServiceConnected() {
    print("override reportBleServiceConnected() in derived class")
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

    reportBleServiceDisconnected()
  }

  func reportBleServiceDisconnected() {
    print("override reportBleServiceDisconnected() in derived class")
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
        peripheral.discoverCharacteristics(ble_data_uuid, for: service)
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
    if let charac = service.characteristics{
      for characteristic in charac {
        dataDictionary[characteristic.uuid] = characteristic
      }
    }
    reportBleServiceCharaceristicsScanned()
  }
  
  func reportBleServiceCharaceristicsScanned(){
    print("override reportBleServiceDisconnected() in derived class")
  }
  
//MARK:- Write(UUID) and Read(UUID) calls

  // Called by derived class to write data to BLE
  func bleWrite(_ write_uuid: CBUUID, writeData: Int32) {
    if let write_characteristic = dataDictionary[write_uuid] {
      let data = Data(bytes: [writeData], count: 4) // Int32 cmd is 4 bytes
      focusMotorPeripheral?.writeValue(data,
                                       for: write_characteristic!,
                                       type: .withoutResponse)
    }
  }
  
  func bleRead(_ readUuid:CBUUID, responder:@escaping (Int32)->Void) -> Bool{
    
    if let read_characteristic = dataDictionary[readUuid] {      // find characteristic
      focusMotorPeripheral?.readValue(for: read_characteristic!) // issue the read
      readResponderDictionary[readUuid] = responder              // handle data when read completes
      return true // characteristic found, data will be provided to responder
    }
    return false // characteristic not found
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
