//
//  ContentView.swift
//  FocusControl
//
//  Created by Barry Bryant on 10/19/21.
//

import SwiftUI

struct MainView: View {
  @ObservedObject var viewModel = MainViewModel();

  var body: some View {
    VStack {
      Text("Focus Control")
      HStack{
        Text("Status: ")
        Text(viewModel.statusString)
      }
      if (viewModel.connected){
        Button("== Disconnect Focus Motor ==",
               action:{viewModel.endBle() } )
          .buttonStyle(.bordered)
          .padding()
      } else {
        Button("== Connect Focus Motor ==",
               action:{viewModel.beginBle() } )
          .buttonStyle(.bordered)
          .padding()
      }
      Text("").padding()

      Text("Focus Mode")
      HStack{
        Text("                                 ") // I feel dirty
        Picker(selection: $viewModel.focusMode,
               label: Text("Focus Mode")) {
          Text("Course").tag(FocusMode.course)
          Text("Medium").tag(FocusMode.medium)
          Text("Fine").tag(FocusMode.fine)
        }.pickerStyle(.segmented)
        Text("                                 ")
      }
      Text("").padding()

      Text("Adjust Focus")
      HStack {
        Button("\nFOCUS \n COUNTER \n CLOCKWISE\n",
               action:{viewModel.decreaseFocus()})
        Button("\nFOCUS \n CLOCKWISE \n \n",
               action:{viewModel.increaseFocus()})
      }.buttonStyle(.bordered)
      HStack{
        Text("Focus Command")
        Text(viewModel.focusMotorCommand.description)
      }
    }

    .onAppear{
      viewModel.viewAppear()
    }
    .onDisappear{
      viewModel.viewDisappear()
    }

  }
}

struct MainView_Previews: PreviewProvider {
  static var previews: some View {
      MainView()
  }
}
