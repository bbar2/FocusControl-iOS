//  ControlViewModel.swift - Created by Barry Bryant on 10/19/21.
//
// Simulate FocusMotor hardware remote control's 20 step rotary encoder.
// Each tap on a UI button emulates one rotary encoder step.
// Each rotary tap (encoder step) changes the FocusMotor position
// command by some number of FocusMotor stepper motor steps.
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
enum FocusMode:Int {
  case course
  case medium
  case fine
}

struct FocusMsg {
  var cmd : Int32
  var val : Int32
}

class ControlViewModel : BleWizardDelegate, ObservableObject  {

  // All UUIDs must match the Arduino C++ focus motor controller and remote control UUIDs
  private let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")

  // Parameter Characteristic UUIDs
  private let FOCUS_POSITION_UUID = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
  private let NUM_MICRO_STEPS_UUID = CBUUID(string: "828b0004-046a-42c7-9c16-00ca297e95eb")

  private let wizard: BleWizard

  @Published var statusString = "Not Connected"

  public var focusMode = FocusMode.medium

  // From C++ Hardware FocusMotor Controller:
  // 20 steps per hardware remote control encoder revolution
  // For 1 to 1 remote control knob to focus knob ratio, multiply encoder count:
  //   x 10 to get 200 ble_central steps per 20 encoder steps
  //   x sprocket ratio of 74/20 knob to motor teeth
  private let fullStepsPerUiInput:Int32 = 10 * 74 / 20
  private var microStepJumper:Int32? // jumper on focus motor, reported via BLE
  
  init() {
    self.wizard = BleWizard(
      serviceUUID: FOCUS_SERVICE_UUID,
      bleDataUUIDs: [FOCUS_POSITION_UUID, NUM_MICRO_STEPS_UUID])
    wizard.delegate = self
  }

  // Called by ViewController to initialize FocusMotorController
  func focusMotorInit() {
    wizard.start()
    statusString = "Searching for Focus-Motor ..."
    initViewModel()
  }
  
  // Called by focusMotorInit & BleDelegate overrides on BLE Connect or Disconnect
  func initViewModel(){
    focusMode = FocusMode.medium
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
    initViewModel()
    statusString = "Connected"
  }
  
  func reportBleServiceDisconnected(){
    initViewModel()
    statusString = "Disconnected"
  }
  
  func reportBleServiceCharaceristicsScanned() {
    // one time read of static value reported by focus motor
    do {
      // note the [capture-list] for the escaping closure who references self.
      // Weak references are always optional, hence the self? optional chain.
      try wizard.bleRead(uuid: NUM_MICRO_STEPS_UUID) { [weak self] resultInt32 in
        self?.microStepJumper = resultInt32
      }
    } catch {
      print(error)
    }
  }
  
  // Clockwise UI action
  func updateMotorCommandCW(){
    wizard.bleWrite(FOCUS_POSITION_UUID,
                    focusMsg:FocusMsg(cmd:20, val:focusStepSize()))
  }

  // Counter Clockwise UI action
  func updateMotorCommandCCW(){
    wizard.bleWrite(FOCUS_POSITION_UUID,
                    focusMsg:FocusMsg(cmd:20, val:-focusStepSize()))
  }
  
  // Determine size of focus step as a function of focusMode
  func focusStepSize() -> Int32 {
    let numMicroSteps = microStepJumper ?? 3 // odd number shows the read never took place

    switch (focusMode) {
    case .course:
      // Match precision of hardware remote control
      return fullStepsPerUiInput * numMicroSteps
    case .medium:
      // Smaller steps for improved focus control. Force multiple of MicroSteps
      return fullStepsPerUiInput / 4 * numMicroSteps
    case .fine:
      // Smallest steps for finest control.  Could go finer with microSteps,
      // but that seems too small in practice. Go with full steps for now.
      return numMicroSteps // one full step
    }
  }
  
}
