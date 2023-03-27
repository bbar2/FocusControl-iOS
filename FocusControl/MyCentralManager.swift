//
//  BleDelegates.swift
//  FocusControl
//
//  Created by Barry Bryant on 3/21/2023
//  Thin wrapper around Core Bluetooth Central Manager
//  Use to create a Central application to talk to a remote BLE peripheral
//
// When using multiple MyPeripheral objects, there can only be one
// MyCentralManager, and one MyCentralManagerDelegate.
// Use one MyPeripheralDelegate for each Peripheral.

import CoreBluetooth
import UIKit

protocol MyCentralManagerDelegate: AnyObject {
  func onCentralManagerStarted()
  func onCentralManagerNotAvailable()
  
  // MyCentralManager forwards these to appropriate MyPeripheral
  func onDidDiscover(newPeripheral: CBPeripheral)
  func onDidConnect(peripheral: CBPeripheral)
  func onDidDisconnect(peripheral: CBPeripheral)
}

class MyCentralManager: NSObject, CBCentralManagerDelegate {
  
  weak var delegate: MyCentralManagerDelegate?

  // Core Bluetooth variables
  private static var cbCentralManager: CBCentralManager?
  private var service_uuid: CBUUID?
  
  // Singleton init
//  override private init(){
//
//  }
  
  // Called by derived class to initialize BLE communication
  // ToDo: Manage by class level logical
  public func start() {
    if MyCentralManager.cbCentralManager == nil {
      MyCentralManager.cbCentralManager = CBCentralManager(delegate: self, queue: nil)
    }
  }
  
  public func findPeripheral(withService: CBUUID) {
    service_uuid = withService
    MyCentralManager.cbCentralManager!.scanForPeripherals(withServices: [service_uuid!],
                                                          options: nil)
  }
  
  public func disconnect(peripheral: CBPeripheral) {
    MyCentralManager.cbCentralManager!.cancelPeripheralConnection(peripheral)
  }
  
  //MARK: CBCentralManagerDelegate

  // Start scanning for BLE DEVICE advertising required SERVICE
  // Must issue scanForPeripherals(withServices: options:) to continue connection process
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if let myCentralManagerDelegate = delegate{
      if (central.state == .poweredOn) {
        myCentralManagerDelegate.onCentralManagerStarted()
      } else {
        myCentralManagerDelegate.onCentralManagerNotAvailable()
      }
    }
  }

  // Once SERVICE found found, stop scanning and connect Peripheral
  // Map Service UUID to newly report peripheral object
  // Must hold a reference to the discoveredPeripheral in onFound.
  func centralManager(_ central: CBCentralManager,
                      didDiscover discoveredPeripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber)
  {
    MyCentralManager.cbCentralManager!.stopScan()
    
    // TODO Need to figure out which peripheral to call here
    if let myCentralManagerDelegate = delegate {
      myCentralManagerDelegate.onDidDiscover(newPeripheral: discoveredPeripheral)
    }

    MyCentralManager.cbCentralManager!.connect(discoveredPeripheral, options: nil)
  }
  
  // Once connected to peripheral, Find desired service
  func centralManager(_ central: CBCentralManager,
                      didConnect connectedPeripheral: CBPeripheral)
  {
    // TODO Need to figure out which peripheral to call here
    if let myCentralManagerDelegate = delegate {
      myCentralManagerDelegate.onDidConnect(peripheral: connectedPeripheral)
    }

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
    
    // TODO Need to figure out which peripheral to call here
    if let myCentralManagerDelegate = delegate {
      myCentralManagerDelegate.onDidDisconnect(peripheral: peripheral)
    }
  }
}
