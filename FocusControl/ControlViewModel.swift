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

struct XlData {
  var x: Float32
  var y: Float32
  var z: Float32
}

class ControlViewModel : BleWizardDelegate, ObservableObject  {
  
  enum BleCentralState {
    case disconnected
    case connecting
    case ready
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
  
  // updated by BLE closure
  @Published var xlData = XlData(x: 0.0, y: 0.0, z: 0.0)
  
  @Published var focusMode = FocusMode.medium
  
  private var bleState = BleCentralState.disconnected
  
  // Focus Service procides focus motor control and focus motor accelerations
  private let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")
  
  // Parameter Characteristic UUIDs
  private let FOCUS_MSG_UUID = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
  private let ACCEL_XYZ_UUID = CBUUID(string: "828b0005-046a-42c7-9c16-00ca297e95eb")
    
  private let wizard: BleWizard
    
  private var connectionTimer = Timer()
  private var uiActive = false; // Set by user action, reset by connection timer
   
  private var uponBleReadyAction : (()->Void)?
  
  init() {
    self.wizard = BleWizard(
      serviceUUID: FOCUS_SERVICE_UUID,
      bleDataUUIDs: [FOCUS_MSG_UUID, ACCEL_XYZ_UUID])
    wizard.delegate = self
    uponBleReadyAction = nil
  }
  
  func bleIsReady() -> Bool {
    return bleState == .ready
  }
  
  // Called once by ViewController to initialize FocusMotorController
  func focusMotorInit() {
    bleState = .connecting
    wizard.start()
    statusString = "Searching for Focus-Motor ..."
    initViewModel()
  }
  
  // Called by focusMotorInit & BleDelegate overrides on BLE Connect or Disconnect
  func initViewModel(){
  }
  
  func disconnect() {
    if (bleState != .disconnected) {
      wizard.disconnect()
    }
  }
  
  // if called while already .ready, upReady will not be executed
  func reconnect(uponReady :(()->Void)? = nil) {
    if (bleState == .disconnected) {
      wizard.reconnect()
    }

    // Queue uponReady closure if .disconnected or .connecting
    if (bleState != .ready) {
      if let action = uponReady {
        uponBleReadyAction = action
      }
    }
  }
  
  // Signal disconnect timer handler that UI is being used.
  func reportUiActive(){
    uiActive = true;
    
    // Any UI input, reconnects the BLE
    if(bleState == .disconnected) {
      reconnect()
    }
  }
  
  // BLE Wizard Delegate "report" callbacks
  func reportBleScanning() {
    statusString = "Scanning ..."
  }
  
  func reportBleNotAvailable() {
    statusString = "BLE Not Available"
  }
  
  func reportBleServiceFound(){
    statusString = "Focus Motor Found"
  }
  
  // BLE Connected, but have not yet scanned for services and characeristics
  func reportBleServiceConnected(){
    initViewModel()
    statusString = "Connected"
  }
    
  // All remote peripheral characteristics scanned - ready for IO
  func reportBleServiceCharaceristicsScanned() {
    
    // Specify closure for ACCEL_XYZ_UUID writes by remote peripheral
    wizard.setNotify(ACCEL_XYZ_UUID) { self.xlData = $0 }
    
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
  
  // If no user interaction for one timerInterval disconnect the BLE link.
  func uiTimerHandler() {
    if (uiActive) { // if ui has been active during this timer interval
      uiActive = false; // remain connected
    } else {
      disconnect()   // else disconnect ble
    }
  }

  func reportBleServiceDisconnected(){
    bleState = .disconnected;
    initViewModel()
    statusString = "Disconnected"
    connectionTimer.invalidate()
  }
  
  // Clockwise UI action
  func updateMotorCommandCW(){
    if (bleState == .ready) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: focusMode.rawValue))
    } else {
      reconnect() {
        self.updateMotorCommandCW()
      }
    }
  }
  
  // Counter Clockwise UI action
  func updateMotorCommandCCW(){
    if (bleState == .ready) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: -focusMode.rawValue))
    } else {
      reconnect() {
        self.updateMotorCommandCCW()
      }
    }
  }
  
  func requestCurrentXl() {
    if (bleState == .ready) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_READ.rawValue,
                                                val: 0))
    } else {
      reconnect() {
        self.requestCurrentXl()
      }
    }
  }
  
  func startXlStream() {
    if (bleState == .ready) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_START.rawValue,
                                                val: 0))
    } else {
      reconnect() {
        self.startXlStream()
      }
    }
  }

  func stopXlStream() {
    if (bleState == .ready) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_STOP.rawValue,
                                                val: 0))
    } else {
      reconnect() {
        self.stopXlStream()
      }
    }
  }
  
}

