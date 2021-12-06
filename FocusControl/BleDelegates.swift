//
//  BleDelegates.swift
//  FocusControl
//
//  Created by Barry Bryant on 12/5/21.
//

import CoreBluetooth

class BleDelegates : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate{

  // All UUIDs must match the Arduino C++ focus motor controller and remote control UUIDs
  private var service_uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
  
  // Parameter Characteristic UUIDs
  private let FOCUS_POSITION_UUID  = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
  private let NUM_MICRO_STEPS_UUID = CBUUID(string: "828b0002-046a-42c7-9c16-00ca297e95eb")

  // Core Bluetooth variables
  private var cbCentralManager       : CBCentralManager!
  private var focusMotorPeripheral   : CBPeripheral?
  private var positionCharacteristic : CBCharacteristic? // Written to BLE

  private var uStepCharacteristic : CBCharacteristic?  // Read from BLE
  private var bleMicroSteps: Int32?

  // Called by FocusMotorController to initialize BLE communication
  func focusMotorBleInit(service_uuid uuid:CBUUID) {
    service_uuid = uuid
    
    //  Starts the sequence of Steps in FocusMotorBle delegates
    cbCentralManager = CBCentralManager(delegate: self, queue: nil)
  }

  // Called by FocusMotorController to send commands over BLE
  func focusMotorSendBleCommand(_ cmd: Int32) {
    if let _ = positionCharacteristic {
      let data = Data(bytes: [cmd], count: 4) // Int32 cmd is 4 bytes
      focusMotorPeripheral?.writeValue(data,
                                       for: positionCharacteristic!,
                                       type: .withoutResponse)
    }
  }
  
  // CBPeripheralDelegate reads microSteps during initialization.
  // microSteps is FocusMotor constant, no need to re-read CBCharacteristic
  func getBleFocusMotorMicroSteps() -> Int32 {
    return bleMicroSteps ?? 4 // good guess if called before BLE read complete
  }


//MARK:- CBCentralManagerDelegate

  // Step 1 - Start scanning for BLE DEVICE advertising required SERVICE
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn)
    {
      reportBleScanning()
      central.scanForPeripherals(withServices: [service_uuid],
                                 options: nil)
    } else
    {
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
        peripheral.discoverCharacteristics(
          [FOCUS_POSITION_UUID, NUM_MICRO_STEPS_UUID],
          for: service)
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

    print("Step 5 - ")
    if let charac = service.characteristics{
      for characteristic in charac {
        if characteristic.uuid == FOCUS_POSITION_UUID {
          positionCharacteristic = characteristic
        } else if (characteristic.uuid == NUM_MICRO_STEPS_UUID) {
          uStepCharacteristic = characteristic

          // Get initial value from characteristic.value in peripheral:didUpdateValueFor
          peripheral.readValue(for: characteristic)
          //peripheral.setNotifyValue(true, for: characteristic) // use if expecting udpates
        }
      }
    }
  }
  
  // Called by peripheral.readValue, or after updates if using peripheral.setNotifyValue
  func peripheral(_ peripheral: CBPeripheral,
                  didUpdateValueFor characteristic: CBCharacteristic,
                  error: Error?)
  {
    if let e = error {
      print("error not nil in peripheral.didUpdateValueFor")
      print(e.localizedDescription)
      return
    }
    
    if (characteristic.uuid == NUM_MICRO_STEPS_UUID) {
      // Copy Data buffer to Int32
      if let data = characteristic.value {
        (data as NSData).getBytes(&bleMicroSteps, length:4)
      }
    }
  }
  
}
