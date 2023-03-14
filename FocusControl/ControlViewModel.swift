//  ControlViewModel.swift - Created by Barry Bryant on 10/19/21.
//
// Simulate FocusMotor hardware remote control's 20 step rotary encoder.
// Each tap on a UI button emulates one rotary encoder step.
// Each rotary tap (encoder step) changes the FocusMotor position
// command by a number of FocusMotor stepper motor steps determined by FocusMode.
//
// The FocusMotor command is scaled for each mode of operation, matching the
// operation of the hardware remote control:
// - Coarse mode: Scaled so 20 UI Taps turns the telescope focus knob one turn.
// - Medium mode: Scaled so 4x20 UI Taps turns the telescope focus knob one
//   turn. Provides finer control over focus operation.
// - Fine mode: the FocusMotor is driven one full stepper motor step for the
//   finest level of focus control.
//
// ControlViewModel implements an iOS remote control "BLE Central":
//   - Establish BLE communication with FocusMotor Peripheral
//   - Read value of microStep jumpers written by FocusMotor
//   - Transmits the FocusMotor commanded position
//   - Converts between CoreBlutooth UInt8 buffers and Int32 values. The
//     FocusMotor hardware is Arduino Nano33BLE based, using Int32 data.
//
// Both the hardware remote control and this app tranmit FocusMotor commands
// via Bluetooth Low Energy (BLE).  Only one can be connected to the actual
// FocusMotor hardware at a time.  If both are turned on, the first to connect
// maintains FocusMotor control. bleConnectionStatus messages inform the UI's
// ViewController of current BLE connection state.

import SwiftUI
import CoreBluetooth

// Define the number of focus motor micro steps for each FocusMode
// From C++ Hardware FocusMotor Controller:
// Raw values = motor steps and should match FocusMotor project FocusMsg.h
enum FocusMode:Int32 {
  case course = 37
  case medium = 9
  case fine   = 2
}

struct RocketFocusMsg {
  var cmd : Int32
  var val : Int32
}

enum CMD:Int32 {
  case STOP = 0x10  // stop execution of commands
  case INIT = 0x11  // Init, No move, set pos to 0, reply with micro_steps_per_step
  case SPOS = 0x12  // set position - focuser moves to new position
  case GPOS = 0x13  // get position - focuser replies with current position
  case MOVE = 0x14  // move val full steps (not micro steps) from current position
  case XL_READ  = 0x15  // Central requests current XL data
  case XL_START = 0x16  // Central ask peripheral to start streaming XL data
  case XL_STOP  = 0x17  // Central ask peripheral to stop streaming XL data
}

struct XlData {
  var x: Float32
  var y: Float32
  var z: Float32
}

// Diconnect BLE if no UI inputs for this long - allows other devices to control focus
let TIMER_DISCONNECT_SEC = 5.0
let RECONNECT_DELAY_SEC = 2.0

class ControlViewModel : BleWizardDelegate, ObservableObject  {
  
  @Published var statusString = "Not Connected"
  
  // uypdated by BLE closure
  @Published var xlData = XlData(x: 0.0, y: 0.0, z: 0.0)
  
  @Published var focusMode = FocusMode.medium
  
  // All UUIDs must match the Arduino C++ focus motor controller and remote control UUIDs
  private let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")
  
  // Parameter Characteristic UUIDs
  private let FOCUS_MSG_UUID = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
  private let ACCEL_XYZ_UUID = CBUUID(string: "828b0005-046a-42c7-9c16-00ca297e95eb")
    
  private let wizard: BleWizard
  
  // BLE is scanning, connnecting, disconnecting - Set by UI actions
  private var bleActive = false;
  
  // BLE is connected and ready for IO - Set by BLE Callbacks
  private var bleConnected = false;
  
  private var connectionTimer = Timer()
  private var uiActive = false; // Set by user action, reset by connection timer
   
  init() {
    self.wizard = BleWizard(
      serviceUUID: FOCUS_SERVICE_UUID,
      bleDataUUIDs: [FOCUS_MSG_UUID, ACCEL_XYZ_UUID])
    wizard.delegate = self
  }
  
  // Called by ViewController to initialize FocusMotorController
  func focusMotorInit() {
    bleActive = true;
    wizard.start()
    statusString = "Searching for Focus-Motor ..."
    initViewModel()
  }
  
  func disconnect() {
    if (bleActive) {
      wizard.disconnect()
    }
    bleActive = false;
  }
  
  func reconnect() {
    if (!bleActive) {
      wizard.reconnect()
    }
    bleActive = true;
  }
  
  // Signal disconnect timer handler that UI is being used.
  func reportUiActive(){
    uiActive = true;
    
    // Any UI input, reconnects the BLE
    if(!bleActive) {
      reconnect()
    }
  }
  
  // Called by focusMotorInit & BleDelegate overrides on BLE Connect or Disconnect
  func initViewModel(){
//    focusMode = FocusMode.medium
  }
  
  func reportBleScanning() {
    statusString = "Scanning ..."
  }
  
  func reportBleNotAvailable() {
    statusString = "BLE Not Available"
  }
  
  func reportBleServiceFound(){
    statusString = "Focus Motor Found"
  }
  
  func reportBleServiceConnected(){
    bleConnected = true
    initViewModel()
    statusString = "Connected"
    
    // Run this timer while connected.
    // If no user interaction for one timerInterval disconnect the BLE link.
    connectionTimer = Timer.scheduledTimer(withTimeInterval: TIMER_DISCONNECT_SEC,
                                           repeats: true) { _ in
      if (self.bleConnected) { // if still connected
        if (self.uiActive) { // if ui has been active during this timer interval
          self.uiActive = false; // remain connected
        } else {
          self.disconnect()   // else disconnect ble
        }
      }
    }
  }
  
  func reportBleServiceDisconnected(){
    bleConnected = false;
    initViewModel()
    statusString = "Disconnected"
    connectionTimer.invalidate()
  }
  
  // At this point in the BLE Connection process, all remote peripheral
  // communication characteristics have been scanned
  func reportBleServiceCharaceristicsScanned() {
    
    // Specify closure for ACCEL_XYZ_UUID writes by remote peripheral
    wizard.setNotify(ACCEL_XYZ_UUID) { self.xlData = $0 }
  }

  // Clockwise UI action
  func updateMotorCommandCW(){
    if (bleConnected) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: focusMode.rawValue))
    } else {
      reconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + RECONNECT_DELAY_SEC) {
        self.updateMotorCommandCW() // reissue command after enough time to connect
      }
    }
  }
  
  // Counter Clockwise UI action
  func updateMotorCommandCCW(){
    if (bleConnected) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.MOVE.rawValue,
                                                val: -focusMode.rawValue))
    } else {
      reconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + RECONNECT_DELAY_SEC) {
        self.updateMotorCommandCCW() // reissue command after enough time to connect
      }
    }
  }
  
  func requestCurrentXl() {
    if (bleConnected) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_READ.rawValue,
                                                val: 0))
    } else {
      reconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + RECONNECT_DELAY_SEC) {
        self.requestCurrentXl() // reissue command after enough time to connect
      }
    }
  }
  
  func startXlStream() {
    if (bleConnected) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_START.rawValue,
                                                val: 0))
    } else {
      reconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + RECONNECT_DELAY_SEC) {
        self.startXlStream() // reissue command after enough time to connect
      }
    }
  }

  func stopXlStream() {
    if (bleConnected) {
      wizard.bleWrite(FOCUS_MSG_UUID,
                      writeData: RocketFocusMsg(cmd: CMD.XL_STOP.rawValue,
                                                val: 0))
    } else {
      reconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + RECONNECT_DELAY_SEC) {
        self.stopXlStream() // reissue command after enough time to connect
      }
    }
  }
  
}
    // since write without response, the write is probably not complete.
    // step 1 - delay for long enough.
    // OK, that worked.
    // Step 2 - use .withresponse.
    //   Will need to pass a closure to bleWrite.
    //   Or better yet --- Use Notify on ACCEL_XYZ_UUID
//    let seconds = 0.1
//    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
//      // note the [capture-list] for the escaping closure who references self.
//      // Weak references are always optional, hence the self? optional chain.
//      self.wizard.bleRead(uuid: self.ACCEL_XYZ_UUID) { [weak self] newXlData in
//        self?.xlData = newXlData
//        print("xlData.x = \(self?.xlData.x ?? 99.1)")
//        print("xlData.y = \(self?.xlData.y ?? 99.2)")
//        print("xlData.z = \(self?.xlData.z ?? 99.3)")
//      }
//    }
//  }

