//
//  MyPeripheral.swift
//  FocusControl
//
//  Created by Barry Bryant on 3/18/23.
//
// Core Bluetooth Peripheral wrapper, using a CentralManager singleton.
// Use one of these for each peripheral, then implement MyPeripheralDelegate
// methods in the object holding a MyPeripheral object.

import CoreBluetooth

protocol MyPeripheralDelegate: AnyObject {
  func onBleRunning()
  func onBleNotAvailable()
  func onFound()
  func onConnected()
  func onDisconnected()
  func onReady()
}

class MyPeripheral :NSObject, CBPeripheralDelegate, MyCentralManagerDelegate {
  
  weak var mpDelegate: MyPeripheralDelegate?
  
  private var centralManager = MyCentralManager.singleton

  private var cbPeripheral: CBPeripheral?

  private var deviceName: String   // Peripheral device name
  private var serviceUuid: CBUUID  // Desired service offered by peripheral
  private var dataUuids: [CBUUID]  // UUID for each BLE data value
  
  // Dictionaries to look up characteristics and responders by UUID
  private var characteristicDictionary: [CBUUID: CBCharacteristic?] = [:]
  private var readResponder: [CBUUID: (Data)->Void] = [:]
  
  init(deviceName: String, serviceUUID: CBUUID, dataUUIDs: [CBUUID])
  {
    self.serviceUuid = serviceUUID
    self.dataUuids = dataUUIDs
    self.deviceName = deviceName

    super.init()  // NSObject
  }
  
  func startBleConnection() {
    centralManager.findPeripheral(named: deviceName,
                                  withService: serviceUuid,
                                  mcmDelegate: self)
  }
  
  func endBleConnection() {
    if let cbPeripheral {
      centralManager.disconnect(peripheral: cbPeripheral)
    }
  }
  
  //MARK: MyCentralManagerDelegate
  func onCentralManagerStarted()
  {
    print("MyPeripheral - onCentralManagerStarted()")
//    startBleConnection()
    if let myPeripheralDelegate = mpDelegate {
      myPeripheralDelegate.onBleRunning()
    }
  }
  
  func onCentralManagerNotAvailable() { // peripheral
    // Don't pass to MyPeripheralDelegate, because there could be multiple peripherals
    // It may make sense for this to be a class (static) method.
    // OR have MyCentralManager call every MyPeripheral.
  }
  
  // WHEN USING MULTIPLE PERIPHERALS the onFound, onConnected, and
  // onDisconnected MyCentralManagerDelegate methods must check peripheral
  // and pass the call to the appropriate object
  func onDidDiscover(newPeripheral: CBPeripheral){
    // Pass to MyPeripheralDelegate

    cbPeripheral = newPeripheral
    cbPeripheral!.delegate = self

    if let myPeripheralDelegate = mpDelegate {
      myPeripheralDelegate.onFound()
    }
  }
  
  // BLE Connected, but have not yet scanned for services and characeristics
  func onDidConnect(peripheral: CBPeripheral){
    // Pass to MyPeripheralDelegate
    if let myPeripheralDelegate = mpDelegate {
      myPeripheralDelegate.onConnected()
    }
  }
  
  func onDidDisconnect(peripheral: CBPeripheral){
    // Pass to MyPeripheralDelegate
    if let myPeripheralDelegate = mpDelegate {
      myPeripheralDelegate.onDisconnected()
    }
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
        peripheral.discoverCharacteristics(dataUuids, for: service)
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
    if let myPeripheralDelegate = mpDelegate {
      myPeripheralDelegate.onReady()
    }
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
  
  //MARK: My BLE IO Methods - used to read and write BLE data
  
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
