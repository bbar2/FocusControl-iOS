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
//   - UUID, and NAME defined in FocusUuid.h
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

class FocusViewModel : MyPeripheralDelegate,
                       ObservableObject  {
  
  enum BleCentralState {
    case disconnected
    case connecting
    case ready
  }
  
  // Acceleration Structure received from Focus Motor
  struct XlData {
    var x: Float32
    var y: Float32
    var z: Float32
  }
  
  // Command structure sent to FocusMotor
  private struct RocketFocusMsg {
    var cmd : Int32
    var val : Int32
  }
  
  // Commands sent to FocusMotor
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
  
  @Published var statusString = "Not Connected"
  @Published var focusMode = FocusMode.medium
  @Published var connectionLock = false // true to prevent connection timeout
  @Published var timerValue: Int = 0
  @Published var pitch: Float = 0.0
  @Published var roll: Float = 0.0
  @Published var yaw: Float = 0.0

  @Published var xlData = XlData(x: 0.0, y: 0.0, z: 0.0)

  // Focus Service provides focus motor control and focus motor accelerations
  private let FOCUS_DEVICE_NAMED = "FocusMotor"
  private let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")
  
  // Parameter Characteristic UUIDs
  private let FOCUS_MSG_UUID = CBUUID(string: "828b0001-046a-42c7-9c16-00ca297e95eb")
  private let ACCEL_XYZ_UUID = CBUUID(string: "828b0005-046a-42c7-9c16-00ca297e95eb")
  
  private var bleState = BleCentralState.disconnected
  private let focusMotor: MyPeripheral
  private var uponBleReadyAction : (()->Void)?
  
  // Disconnect BLE if no UI inputs for this long, so other devices can control focus
  private let TIMER_DISCONNECT_SEC = 10
  private var connectionTimer = Timer()
  
  private let PI = Float(3.1415927)

  func toDeg(_ rad:Float) -> Float {
    return rad * 180 / PI
  }

  func toRad(_ deg:Float) -> Float {
    return deg * PI / 180
  }

    
  // figure out where this should go
  func calcAngles() {
    
    let Ax = xlData.x
    let Ay = xlData.y
    let Az = xlData.z
    
    // Angles in telescope frame
    let theta = toRad(27.38) // local lattitude, or Mount pitch
    let ct = cos(theta)
    let st = sin(theta)
    
    let phi = acos(Az / ct)
    let sp = sin(phi)
    
    // using Ax equation
    let A = st
    let B = -ct*st
    let R = sqrt(A*A + B*B)
    let alpha = atan(B/A)*0.0
    let psi = acos(Ax/R) - alpha
    
    pitch = toDeg(theta)
    roll  = toDeg(phi)
    yaw   = toDeg(psi)
    
    // angles in earth frame
//    pitch = toDeg(atan(Ax / sqrt(Ay*Ay + Az*Az))) // theta pitch around Y
//    roll  = toDeg(atan(Ay / sqrt(Ax*Ax + Az*Az))) // phi rotation around X
//    yaw   = toDeg(atan(sqrt(Ax*Ax + Ay*Ay) / Az)) // psi rotation around Z
    
  }
  
  init() {
    focusMotor = MyPeripheral(deviceName: FOCUS_DEVICE_NAMED,
                              serviceUUID: FOCUS_SERVICE_UUID,
                              dataUUIDs: [FOCUS_MSG_UUID, ACCEL_XYZ_UUID])
    uponBleReadyAction = nil
    focusMotor.mpDelegate = self
    connectBle()
  }
  
  // Called once by ViewController
  func viewModelInit() {
    statusString = "Searching for Focus-Motor ..."
  }
  
  // used by FocusView for UI color control
  func bleIsReady() -> Bool {
    return bleState == .ready
  }
  
  func connectBle(uponReady :(()->Void)? = nil) {
    if (bleState == .disconnected) {
      statusString = "Connecting"
      bleState = .connecting
      focusMotor.startBleConnection()
    }
    if let action = uponReady{
      uponBleReadyAction = action
    }
  }
  
  func disconnectBle() {
    if (bleState != .disconnected) {
      focusMotor.endBleConnection()
    }
  }
  
  // Signal disconnect timer handler that UI is being used.
  func reportUiActive(){
    timerValue = TIMER_DISCONNECT_SEC
    
    // Any UI input, reconnects the BLE
    if(bleState == .disconnected) {
      connectBle()
    }
  }
  
  // If no UI interaction for one timerInterval disconnect the BLE link.
  func uiTimerHandler() {
    timerValue -= 1
    
    if (!connectionLock && timerValue <= 0) {
      disconnectBle()   // disconnect ble
    }
  }
  
  //MARK: UI Actions
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
  
  //MARK: MyPeripheralDelegate
  
  func onFound(){
    statusString = "Focus Motor Found"
  }
  
  // BLE Connected, but have not yet scanned for services and characeristics
  func onConnected(){
    statusString = "Connected"
  }
  
  func onDisconnected(){
    bleState = .disconnected;
    statusString = "Disconnected"
    connectionTimer.invalidate()
    connectionLock = false
  }
  
  func onReady() {
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
    // - peripheral uses a common bleRead and setNotify for all data types
    // - Caller closure is common format for all data types, but a klunky mess.
    // - This avoid approach 3's "escaping closure capture inout param" problem by:
    //   -- self reference to store result, vs passing inout param in closure
    focusMotor.setNotify(ACCEL_XYZ_UUID) { [weak self] (buffer:Data)->Void in
      let numBytes = min(buffer.count, MemoryLayout.size(ofValue: self!.xlData))
      withUnsafeMutableBytes(of: &self!.xlData) { pointer in
        _ = buffer.copyBytes(to:pointer, from:0..<numBytes)
      }
      self?.calcAngles()
    }
    
    // Approach 3: Use Generic inout data and construct closure in setNotify (or bleRead)
    // - All the benefits of Approach 2, with a single Data type for stored
    //   closures, setNofity, and bleRead
    // - Cleanest calling format
    // - Doesn't work due to "escaping closure capturing inout parameter"
    // - There may be a solution with deferred copy of a local variable in setNotify3
    //    focusMotor.setNotify3(ACCEL_XYZ_UUID, readData: &xlData)
    
    // Start timer to disconnect when UI becomes inactive
    timerValue = TIMER_DISCONNECT_SEC
    connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0,
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
  
}

