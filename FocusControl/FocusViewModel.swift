//  ControlViewModel.swift - Created by Barry Bryant on 10/19/21.
//
// Simulate FocusMotor hardware remote control's 20 step rotary encoder.
//   Each tap on a UI button emulates one rotary encoder step.
//   Each encoder step (or UI tap) changes the FocusMotor position
//   command by a number of FocusMotor stepper motor steps determined by FocusMode.
//
// ControlViewModel implements an iOS remote control "BLE Central":
//   - Establish BLE communication with FocusMotor Peripheral
//   - Transmits the FocusMotor commanded position
//   - Converts between CoreBlutooth UInt8 buffers and Int32 values. The
//     FocusMotor hardware is Arduino Nano33BLE based, using Int32 data.
//
// The FocusMotor command is scaled for each mode of operation, matching the
//   operation of the hardware remote control:
//   - Coarse mode: Scaled so 20 UI Taps turns the telescope focus knob one turn.
//   - Medium mode: Scaled so 4x20 UI Taps turns the telescope focus knob one
//     turn. Provides finer control over focus operation.
//   - Fine mode: the FocusMotor is driven one full stepper motor step for the
//     finest level of focus control.
//
// Data Transmitted over BLE must match C++ FocusMotor Controller definitions:
//   - RocketFocusMsg structure, defined in FocusMsg.h
//   - XLData structure, defined in FocusMsg.h
//   - CMD raw values, defined in FocusMsg.h
//   - FocusMode raw values, defined in FocusMsg.h
//   - UUID, defined in FocusUuid.h
//
// This app, the hardware remote control, and the MacOS Indigo apps tranmit
//   FocusMotor commands via Bluetooth Low Energy (BLE).
//   - Only one can connect to the FocusMotor hardware at a time.
//   - The first to connect wins. Disconnect after a period of inaction to allow
//     other devices to connect as needed.
//   - bleConnectionStatus messages inform the UI's ViewController of current BLE
//     connection state.

import SwiftUI
import CoreBluetooth

// Define the number of focus motor micro steps for each FocusMode
// Raw values = motor steps and should match FocusMotor project FocusMsg.h
enum FocusMode:Int32 {
  case course = 37
  case medium = 9
  case fine   = 2
}

// Focus Service provides focus motor control and focus motor accelerations
let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")

// Parameter Characteristic UUIDs
let FOCUS_MSG_UUID = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
let ACCEL_XYZ_UUID = CBUUID(string: "828b0005-046a-42c7-9c16-00ca297e95eb")


class FocusViewModel : MyCentralManagerDelegate,
                       MyPeripheralDelegate,
                       ObservableObject  {
  
  enum BleCentralState {
    case off
    case disconnected
    case connecting
    case ready
  }
  
  struct XlData {
    var x: Float32
    var y: Float32
    var z: Float32
  }

  private struct RocketFocusMsg {
    var cmd : Int32
    var val : Int32
  }

  private enum CMD:Int32 {
    case STOP = 0x10  // stop execution of commands
    case INIT = 0x11  // Init, No move, set pos to 0, reply with micro_steps_per_step
    case SPOS = 0x12  // set position - focuser moves to new position
    case GPOS = 0x13  // get position - focuser replies with current position
    case MOVE = 0x14  // move val full steps (not micro steps) from current position
    case XL_READ  = 0x15  // Central requests current XL data
    case XL_START = 0x16  // Central ask peripheral to start streaming XL data
    case XL_STOP  = 0x17  // Central ask peripheral to stop streaming XL data
  }

  // Disconnect BLE if no UI inputs for this long - allows other devices to control focus
  private let TIMER_DISCONNECT_SEC = 5.0
  
  @Published var statusString = "Not Connected"
  
  // updated by Notify using BLE closure
  @Published var xlData = XlData(x: 0.0, y: 0.0, z: 0.0)
  
  @Published var focusMode = FocusMode.medium
  
  private var bleState = BleCentralState.off
    
  private let centralManager: MyCentralManager
  
  private let focusMotor: MyPeripheral
    
  private var connectionTimer = Timer()
  private var uiActive = false; // Set by user action, reset by connection timer
  @Published var connectionLock = false // true to prevent connection timeout
  
//  private var focusMotor: CBPeripheral
   
  private var uponBleReadyAction : (()->Void)?
  
  init() {
    centralManager = MyCentralManager()
    focusMotor = MyPeripheral(serviceUUID: FOCUS_SERVICE_UUID,
                              bleDataUUIDs: [FOCUS_MSG_UUID,
                                             ACCEL_XYZ_UUID])
    uponBleReadyAction = nil
    centralManager.delegate = self
    focusMotor.delegate = self
    print(".delegate(s) = FocusViewModel")
  }
  
  func bleIsReady() -> Bool {
    return bleState == .ready
  }
  
  // Called once by ViewController to initialize FocusMotorController
  func focusMotorInit() {
    centralManager.start()
    statusString = "Searching for Focus-Motor ..."
    initViewModel()
  }
  
  // Called by focusMotorInit & BleDelegate overrides on BLE Connect or Disconnect
  func initViewModel(){
  }
  
  func disconnectBle() {
    if (bleState != .disconnected) {
      if let peripheral = focusMotor.getPeripheral() {
        centralManager.disconnect(peripheral: peripheral)
      }
    }
  }
  
  func connectBle(uponReady :(()->Void)? = nil) {
    if (bleState == .disconnected) {
      bleState = .connecting
      centralManager.findPeripheral(withService: FOCUS_SERVICE_UUID)
    }
    if let action = uponReady{
      uponBleReadyAction = action
    }
  }
  
  // Signal disconnect timer handler that UI is being used.
  func reportUiActive(){
    uiActive = true;
    
    // Any UI input, reconnects the BLE
    if(bleState == .disconnected) {
      connectBle()
    }
  }
  
  // BLE Wizard Delegate "report" callbacks
  func onCentralManagerStarted() {
    bleState = .disconnected
    statusString = "Ready ..."
    print("onCentralManagerStarted")
    connectBle(); // First connection, upon BLE initization
  }
  
  func onCentralManagerNotAvailable() {
    bleState = .disconnected
    statusString = "BLE Not Available"
  }
  
  func onFound(peripheral: CBPeripheral){
    statusString = "Focus Motor Found"
    focusMotor.setPeripheral(peripheral)
    peripheral.delegate = focusMotor
    print("onFound")
  }
  
  // BLE Connected, but have not yet scanned for services and characeristics
  func onConnected(peripheral: CBPeripheral){
    initViewModel()
    statusString = "Connected"
  }
    
  // All remote peripheral characteristics scanned - ready for IO
  func onReady(peripheral: CBPeripheral) {
    print("onReady called by FMP")

    // Setup Notifications, to process writes from the FocusMotor peripheral

    // Approach 1:  Unique closure signature for each data type.
    // - peripheral requires access to each datatype used
    // - peripheral(didUpdateValueFor) must match closure signature to UUID
    // - peripheral must keep an array of closures for each data type
    // - peripheral requires a bleRead and setNotify for each type read
    // - Caller syntax is simple and clean
//    focusMotor.setNotify(ACCEL_XYZ_UUID) { self.xlData = $0 }

    // Approach 2: Common closure signature using Swift Data type.
    // - peripheral(didUpdateValueFor) requires no mods for any data type
    // - peripheral uses a common bleRead and setNotify for all data types used
    // - Caller closure is common format for all data types, but a klunky mess.
    // - How's this avoid approach 3's "escaping closure capture inout param" problem??
    // - self reference to store final result, vs inout param, avoids approach 3's problem
    focusMotor.setNotify(ACCEL_XYZ_UUID) { [weak self] (buffer:Data)->Void in
      let numBytes = min(buffer.count, MemoryLayout.size(ofValue: self!.xlData))
      withUnsafeMutableBytes(of: &self!.xlData) { pointer in
        _ = buffer.copyBytes(to:pointer, from:0..<numBytes)
      }
    }
    
    // Approach 3: Use Generic inout data and construct closure in setNotify (or bleRead)
    // - All the benefits of Approach 2, with a single Data type for stored
    //   closures, setNofity, and bleRead
    // - Cleanest calling format
    // - Doesn't work due to "escaping closure capturing inout parameter"
    // - There may be a solution with deferred copy of a local variable in setNotify3
//    focusMotor.setNotify3(ACCEL_XYZ_UUID, readData: &xlData)

    // Start timer to disconnect when UI becomes inactive
    connectionTimer = Timer.scheduledTimer(withTimeInterval: TIMER_DISCONNECT_SEC,
                                           repeats: true) { _ in
      self.uiTimerHandler()
    }

    statusString = "Ready"
    bleState = .ready

    // Check for saved action to complete once BLE is ready
    if let bleReadyAction = uponBleReadyAction {
      bleReadyAction()
      uponBleReadyAction = nil
    }
  }
  
  // If no UI interaction for one timerInterval disconnect the BLE link.
  func uiTimerHandler() {
    if (!connectionLock && !uiActive) {
      disconnectBle()   // disconnect ble
    }
    uiActive = false; // always reset ui interaction logical
  }

  func onDisconnected(peripheral: CBPeripheral){
    bleState = .disconnected;
    initViewModel()
    statusString = "Disconnected"
    connectionTimer.invalidate()
    connectionLock = false
  }
  
  // Clockwise UI action
  func updateMotorCommandCW(){
    if (bleState == .ready) {
      focusMotor.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: focusMode.rawValue))
    } else {
      connectBle() {
        self.updateMotorCommandCW()
      }
    }
  }
  
  // Counter Clockwise UI action
  func updateMotorCommandCCW(){
    if (bleState == .ready) {
      focusMotor.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: -focusMode.rawValue))
    } else {
      connectBle() {
        self.updateMotorCommandCCW()
      }
    }
  }
  
  func requestCurrentXl() {
    if (bleState == .ready) {
      focusMotor.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_READ.rawValue,
                                                val: 0))
    } else {
      connectBle() {
        self.requestCurrentXl()
      }
    }
  }
  
  func startXlStream() {
    if (bleState == .ready) {
      focusMotor.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_START.rawValue,
                                                val: 0))
    } else {
      connectBle() {
        self.startXlStream()
      }
    }
  }

  func stopXlStream() {
    if (bleState == .ready) {
      focusMotor.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_STOP.rawValue,
                                                val: 0))
    } else {
      connectBle() {
        self.stopXlStream()
      }
    }
  }
  
}

