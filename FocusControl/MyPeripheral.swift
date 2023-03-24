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
  
  // Dictionaries to look up characteristics and responders by UUID
  private var characteristicDictionary: [CBUUID: CBCharacteristic?] = [:]
  private var readResponder: [CBUUID: (Data)->Void] = [:]
  
  private var cbPeripheral: CBPeripheral?
  var peripheral: CBPeripheral? {
    get {
      return cbPeripheral// ?? nil
    }
    set {
      cbPeripheral = newValue
      cbPeripheral!.delegate = self
    }
  }
  
  init(serviceUUID: CBUUID, bleDataUUIDs: [CBUUID]) {
    self.service_uuid = serviceUUID
    self.ble_data_uuids = bleDataUUIDs
    cbPeripheral = nil
    super.init()
  }
  
  //MARK: CBPeripheralDelegate Methods
  
  // Once service found, look for specific parameter characteristics
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
  
  //MARK: My BLE IO Methods - bleWrite(UUID), bleRead(UUID) and setNotify(UUID)
  
  // Write single WriteType data item to BLE
  func bleWrite<WriteType>(_ write_uuid: CBUUID, writeData: WriteType) {
    if let write_characteristic = characteristicDictionary[write_uuid] {
      let data = Data(bytes: [writeData], count: MemoryLayout<WriteType>.size)
      cbPeripheral?.writeValue(data,
                             for: write_characteristic!,
                             type: .withoutResponse)
    }
  }
  
  // Example bleRead or setNotify closure. Copy and change xlData to any data item
  // focusMotor.setNotify(ACCEL_XYZ_UUID) { [weak self] (buffer:Data)->Void in
  //   let numBytes = min(buffer.count, MemoryLayout.size(ofValue: self!.xlData))
  //   withUnsafeMutableBytes(of: &self!.xlData) { pointer in
  //     _ = buffer.copyBytes(to:pointer, from:0..<numBytes)
  //   }
  
  // Issue a nowait BLE read
  // Closure copies Characterstic.value:Data to application data type.
  func bleRead(_ uuid: CBUUID,
               onReadResult: @escaping (Data)->Void) {
    
    readResponder[uuid] = onReadResult  // handle data when read completes
    
    if let readCharacteristic = characteristicDictionary[uuid] { // find characteristic
      if let peripheral = cbPeripheral {
        peripheral.readValue(for: readCharacteristic!) // issue the read
      }
    }
  }
  
  // Set a characterstic to update a local variable whenever peripheral writes
  // Closure copies Characterstic.value:Data bytes to any application data type.
  func setNotify(_ uuid: CBUUID,
                 onReadResult: @escaping (Data)->Void) {
    
    // Save closure to execute upon Notification (peripheral write complete)
    readResponder[uuid] = onReadResult
    
    // Look up the Characteristic, and enable nofication
    if let notifyCharacteristic = characteristicDictionary[uuid] {
      if let peripheral = cbPeripheral {
        peripheral.setNotifyValue(true, for: notifyCharacteristic!);
      }
    }
  }
  
  // Work in progress - simplify use by building closure in setNotify.
  // if this works, bleRead can be modified similarly.
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
      if let peripheral = cbPeripheral {
        peripheral.setNotifyValue(true, for: notifyCharacteristic!);
      }
    }
  }
  
}
