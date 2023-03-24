//
//  BleDelegates.swift
//  FocusControl
//
//  Created by Barry Bryant on 3/21/2023
//  Thin wrapper around Core Bluetooth Central Manager
//  Use to create a Central application to talk to a remote BLE peripheral
//

import CoreBluetooth
import UIKit

protocol MyCentralManagerDelegate: AnyObject {
  func onCentralManagerStarted()
  func onCentralManagerNotAvailable()
  func onFound(newPeripheral: CBPeripheral)
  func onConnected(peripheral: CBPeripheral)
  func onDisconnected(peripheral: CBPeripheral)
}

class MyCentralManager: NSObject, CBCentralManagerDelegate {
  
  weak var delegate: MyCentralManagerDelegate?

  // Core Bluetooth variables
  private var cbCentralManager: CBCentralManager?
  private var service_uuid: CBUUID?
  
  // Called by derived class to initialize BLE communication
  // ToDo: Manage by class level logical
  public func start() {
    if cbCentralManager == nil {
      cbCentralManager = CBCentralManager(delegate: self, queue: nil)
    }
  }
  
  public func findPeripheral(withService: CBUUID) {
    service_uuid = withService
    cbCentralManager!.scanForPeripherals(withServices: [service_uuid!], options: nil)
  }
  
  public func disconnect(peripheral: CBPeripheral) {
    cbCentralManager!.cancelPeripheralConnection(peripheral)
  }
  
  //MARK: CBCentralManagerDelegate

  // Step 1 - Start scanning for BLE DEVICE advertising required SERVICE
  // Must issue scanForPeripherals(withServices: options:) to continue connection process
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn) {
      delegate?.onCentralManagerStarted()
    } else {
      delegate?.onCentralManagerNotAvailable()
    }
  }

  // Step 2 - Once SERVICE found found, stop scanning and connect Peripheral
  // Map Service UUID to newly report peripheral object
  // Must hold a reference to the discoveredPeripheral in onFound.
  func centralManager(_ central: CBCentralManager,
                      didDiscover discoveredPeripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber)
  {
    cbCentralManager!.stopScan()
    delegate?.onFound(newPeripheral: discoveredPeripheral)

    cbCentralManager!.connect(discoveredPeripheral, options: nil)
  }
  
  // Step 3 - Once connected to peripheral, Find desired service
  func centralManager(_ central: CBCentralManager,
                      didConnect connectedPeripheral: CBPeripheral)
  {
    delegate?.onConnected(peripheral: connectedPeripheral)

    connectedPeripheral.discoverServices([service_uuid!]) // already know it has it!
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
    
    delegate?.onDisconnected(peripheral: peripheral)
  }
}
