//
//  BleDelegates.swift
//  FocusControl
//
//  Created by Barry Bryant on 3/21/2023
//  Wrapper around Core Bluetooth Central Manager
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

// Singleton
class MyCentralManager: NSObject, CBCentralManagerDelegate {

  // Class variable
  static let singleton = MyCentralManager()

  // Core Bluetooth members
  private var cbCentralManager: CBCentralManager?
  private var nameToService: [String: CBUUID] = [:]
  private var nameToMcmDelegate: [String: MyCentralManagerDelegate] = [:]
 
  // Singleton init
  private override init() {
    super.init()
    cbCentralManager = CBCentralManager(delegate: self, queue: nil)
  }
    
  // The peripheral withService must also have the named name
  public func findPeripheral(named peripheralName: String,
                             withService peripheralService: CBUUID,
                             mcmDelegate: MyCentralManagerDelegate)
  {
    // Update Dictionaries used by CBCentralManagerDelegate to map to MyPeripheral(s)
    nameToMcmDelegate[peripheralName] = mcmDelegate
    nameToService[peripheralName] = peripheralService
    
    // Start Core BlueTooth connection process
    cbCentralManager!.scanForPeripherals(withServices: [peripheralService])
  }
  
  public func disconnect(peripheral: CBPeripheral) {
    cbCentralManager!.cancelPeripheralConnection(peripheral)
  }
  
  //MARK: CBCentralManagerDelegate
  // Inform all MyPeripheral devices that Central has Started or is NotAvailable
  func centralManagerDidUpdateState(_ central: CBCentralManager)
  {
    // There is a good chance that this will still be empty
    // TODO - this is almost certainly not populated yet.
    // TODO - only  way to proceed, is for model to issue a findPeripheral with
    // some other mechanism.  Yet, findPeripheral really can't go until this has.
    // This has potential race problems.
    for (_, myPeripheral) in nameToMcmDelegate {
      if (central.state == .poweredOn) {
        myPeripheral.onCentralManagerStarted()
      } else {
        myPeripheral.onCentralManagerNotAvailable()
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
    cbCentralManager!.stopScan() // TODO - deal with scanning for more than once device

    // Select the associated MyCentralManagerDelegate (MyPeripheral Object)
    if let discoveredName = discoveredPeripheral.name {
      if let myPeripheral = nameToMcmDelegate[discoveredName] {
        myPeripheral.onDidDiscover(newPeripheral: discoveredPeripheral)
      } else {
        print("Unexpected name in didDiscover: \(discoveredName)")
      }
    } else {
      print("discoveredPeripheral has no name")
    }
    
    cbCentralManager!.connect(discoveredPeripheral, options: nil)
  }
  
  // Once connected to peripheral, Find desired service
  func centralManager(_ central: CBCentralManager,
                      didConnect connectedPeripheral: CBPeripheral)
  {
    // Select the associated MyCentralManagerDelegate (MyPeripheral Object)
    if let connectedName = connectedPeripheral.name {
      if let myPeripheral = nameToMcmDelegate[connectedName] {
        myPeripheral.onDidConnect(peripheral: connectedPeripheral)
        if let peripheralService = nameToService[connectedName] {
          connectedPeripheral.discoverServices([peripheralService])
        } else {
          print("Can't find peripheralService in didConnect")
        }
      } else {
        print("Unexpected name in didConnect: \(connectedName)")
      }
    } else {
      print("connectedPeripheral has no name")
    }
  }
  
  // If disconnected - resume  scanning for Focus Motor peripheral
  func centralManager(_ central: CBCentralManager,
                      didDisconnectPeripheral disconnectedPeripheral: CBPeripheral,
                      error: Error?)
  {
    if let e = error {
      print("error not nil in centralManager.didDisconnectPeripheral")
      print(e.localizedDescription)
    }
    
    print("centralManager.didDisconnectPeripheral")

    // Select the associated MyCentralManagerDelegate (MyPeripheral Object)
    if let disconnectedName = disconnectedPeripheral.name {
      if let myPeripheral = nameToMcmDelegate[disconnectedName] {
        myPeripheral.onDidDisconnect(peripheral: disconnectedPeripheral)
      } else {
        print("Unexpected name in didDisconnectPeripheral: \(disconnectedName)")
      }
    } else {
      print("disconnectedPeripheral has no name")
    }
  }
}
