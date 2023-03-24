//
//  MyPeripheral.swift
//  FocusControl
//
//  Created by Barry Bryant on 3/18/23.
//
// Wrapper around Core Bluetooth Peripheral.
// Use one of these for each peripheral, then implement MyPeripheralDelegate
// methods in the object holding a MyPeripheral object.
// That same object is probably handling MyCentralManagar and it's delegates too.

import CoreBluetooth

protocol MyPeripheralDelegate: AnyObject {
  func onReady(peripheral: CBPeripheral)
}

class MyPeripheral :NSObject, CBPeripheralDelegate {
  
  weak var delegate: MyPeripheralDelegate?
  
  private var service_uuid: CBUUID     // UUID of desired service
  private var ble_data_uuids: [CBUUID]  // UUID for each BLE data value
 
  private var peripheral: CBPeripheral?
  private var characteristicDictionary: [CBUUID: CBCharacteristic?] = [:] // uuid to characteristic mapping

  private var readResponder: [CBUUID: (Data)->Void] = [:]

  init(serviceUUID: CBUUID, bleDataUUIDs: [CBUUID]) {
    self.service_uuid = serviceUUID
    self.ble_data_uuids = bleDataUUIDs
    peripheral = nil
    super.init()
  }
  
  func setPeripheral(_ newPeripheral: CBPeripheral) {
    peripheral = newPeripheral
    peripheral!.delegate = self
  }
  func getPeripheral() -> CBPeripheral? {
    return peripheral
  }
    
  // Once service found, look for specific parameter characteristics
  func peripheral(_ peripheral: CBPeripheral,
                  didDiscoverServices error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didDiscoverServices")
      print(e.localizedDescription)
      return
    }
    print("FMP didDiscoverServices")
    if let services = peripheral.services {
      for service in services {
        peripheral.discoverCharacteristics(ble_data_uuids, for: service)
      }
    }
  }
  
  // Store CBCharacterstic values for future communication
  func peripheral(_ peripheral: CBPeripheral,
                  didDiscoverCharacteristicsFor service: CBService,
                  error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didDiscoverCharacteristicsFor")
      print(e.localizedDescription)
      return
    }
    print("FMP didDiscoverCharacteristics")
    
    // Create a dictionary to find characteristics, via UUID
    if let characteristics = service.characteristics {
      for characteristic in characteristics {
        characteristicDictionary[characteristic.uuid] = characteristic
      }
    }
    delegate!.onReady(peripheral: peripheral)
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
    
    // call UUID's responder with characteristics.value:Data
    if let responder = readResponder[characteristic.uuid] {
      responder(characteristic.value!)
    }
  }
  
  //MARK:- bleWrite(UUID), bleRead(UUID) and setNotify(UUID) functions
  
  // Write single WriteType data item to BLE
  func bleWrite<WriteType>(_ write_uuid: CBUUID, writeData: WriteType) {
    if let write_characteristic = characteristicDictionary[write_uuid] {
      let data = Data(bytes: [writeData], count: MemoryLayout<WriteType>.size)
      peripheral?.writeValue(data,
                             for: write_characteristic!,
                             type: .withoutResponse)
    }
  }
  
  // Issue a nowait BLE read
  // Closure copies Characterstic.value:Data to application data type.
  func bleRead(_ uuid: CBUUID,
               onReadResult: @escaping (Data)->Void) {

    readResponder[uuid] = onReadResult  // handle data when read completes

    if let readCharacteristic = characteristicDictionary[uuid] { // find characteristic
      if let peripheral = peripheral {
        peripheral.readValue(for: readCharacteristic!) // issue the read
      }
    }
  }

  // Set a characterstic to update a local variable whenever peripheral writes
  // Closure copies Characterstic.value:Data to application data type.
  func setNotify(_ uuid: CBUUID,
                 onReadResult: @escaping (Data)->Void) {

    // Save closure to execute upon Notification (peripheral write complete)
    readResponder[uuid] = onReadResult

    // Look up the Characteristic, and enable nofication
    if let notifyCharacteristic = characteristicDictionary[uuid] {
      if let peripheral = peripheral {
        peripheral.setNotifyValue(true, for: notifyCharacteristic!);
      }
    }
  }

  // let closure access local variable to avoid inout param in closure
  func setNotify3<ReadType>(_ uuid: CBUUID, readData: inout ReadType) {
    
    var localCopy = readData
    readResponder[uuid] = { (buffer:Data)->Void in
      _ = withUnsafeMutableBytes(of:  &localCopy) { pointer in
        buffer.copyBytes(to:pointer, from:0..<buffer.count)
      }
//      readData = localCopy // need this to make it work
    }
        
    // Look up the Characteristic, and enable nofication
    if let notifyCharacteristic = characteristicDictionary[uuid] {
      if let peripheral = peripheral {
        peripheral.setNotifyValue(true, for: notifyCharacteristic!);
      }
    }
  }
    
}
