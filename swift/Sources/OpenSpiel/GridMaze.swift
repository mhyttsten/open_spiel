import Foundation


public typealias GridMazeDefinition = [[State]]
typealias ProbRewardTState = (prob:Float, reward:Float, state:State)

//----
public class GridMazeEnvironment {
  
  //----
  var _maze: GridMazeDefinition = []
  
  var _rewardBounceBack: Float = -1  // E.g, Taking Left from (0,0) will give S',R = (0,0), _bounceReward
  var _rowCount = -1
  var _colCount = -1
  
  //----
  public init(rowCount: Int, colCount: Int, rewardSpaces: Float = -1, rewardBounceBack: Float = -1) {
    
    var maze: Array<Array<State>> = []
    maze.reserveCapacity(rowCount)
    for _ in 0..<rowCount {
      var row: Array<State> = []
      for _ in 0..<colCount {
        row.append(SPACE(reward: rewardSpaces))
      }
      maze.append(row)
    }
    _maze = maze
    _rewardBounceBack = rewardBounceBack
    
    precondition(_maze.count > 0, "Maze must have at least 1 row")
    _rowCount = _maze.count
    for (rindex, row) in _maze.enumerated() {
      if _colCount == -1 {
        precondition(row.count > 0, "Maze must have at least 1 column")
        _colCount = row.count
      } else {
        precondition(row.count == _colCount, "All columns in maze must be of size \(_colCount)")
      }
      for (cindex, state) in row.enumerated() {
        state.initialize(mazeEnv: self, row: rindex, col: cindex)
      }
    }
  }
  
  //---
  public subscript(row: Int, col: Int) -> State {
    get { return _maze[row][col] }
    set {
      _maze[row][col] = newValue
      _maze[row][col]._row = row
      _maze[row][col]._col = col
    }
  }
  
  //----
  public func reset() -> State {
    let state = _maze.flatMap { $0 }.filter { $0._isStart }
    precondition(state.count == 1, "Need 1, but also only supports 1 start state")
    let rv = state[0]
    precondition(rv._isVisitable, "Cannot return a non-visitable state from reset()");
    precondition(rv._isStart, "Expected to return an _isStart state from reset()");
    return state[0]
  }
  
  //----
  public func step(state: State, action: Action) -> (r: Float, s: State) {
    let probRewardStateList = probeActionWithProbabilities(fromState: state, takingAction: action)
    let probabilities = probRewardStateList.map { $0.prob }
    let selectedIndex = randomNumber(probabilities: probabilities)
    let selectedElem = probRewardStateList[selectedIndex]
    return (selectedElem.reward, selectedElem.state)
  }
  
  //----
  func probeActionWithProbabilities(fromState: State, takingAction: Action) -> [ProbRewardTState] {
    precondition(fromState._isVisitable,
                 "Cannot probeActionWithProbabilities from non-visitable state @ (\(fromState._row),\(fromState._col))")
    
    // Get the new state (sprime) takingAction from self
    let bounced: Bool
    let sprime: State
    (sprime, bounced) = getSPrimeWithBounce(fromState: fromState, takingAction: takingAction)
    if (bounced) {  // If we bounced, then return is simple, we remain where we are
      return [(Float(1.0), _rewardBounceBack, fromState)]
    }
    
    // Single welcome at target state
    let jsl = sprime._jumpProbabilities
    if jsl.count == 0 {
      return [(Float(1.0), sprime._reward, sprime)]
    }
    
    var result = [ProbRewardTState]()
    for jsi in jsl.indices {
      let s = getTargetStateFromJumpSpecification(fromState: fromState, jsState: sprime, js: jsl[jsi].js)
      precondition(jsl[jsi].js == .Welcome || s.is100PercentWelcomingState(), "We only support 1 level of jump probabilities")
      result.append((jsl[jsi].p, s._reward, s))
    }
    return result
  }
  
  //----
  func probeAction(fromState: State, takingAction: Action) -> (reward: Float, nextState: State) {
    let l = probeActionWithProbabilities(fromState: fromState, takingAction: takingAction)
    precondition(l.count != 1, "probeAction does not support probabilities in target state jump specifications")
    return (l[0].prob, l[0].state)
  }
  
  //----
  func getTargetStateFromJumpSpecification(fromState: State, jsState: State, js: JumpSpecification) -> State {
    let rv: State
    switch js {
    case .Welcome:
      rv = jsState
    case .BounceBack:
      rv = fromState
    case let .Absolute(row,col):
      rv = _maze[row][col]
    case let .Relative(row, col):
      rv = _maze[jsState._row+row][jsState._col+col]
    }
    // We only support 1-step jumps. I.e. we cannot jump to a state having JSs specifying additional jumps
    precondition(js == .Welcome || rv.is100PercentWelcomingState(), "In state (\(fromState._row),\(fromState._col)). Target state (\(rv._row),\(rv._col)) was not purely welcoming")
    return rv
  }
  
  //----
  // Returns new position takingAction fromState
  // If attempting to go beyond a border position, it is bounced back to originating state
  // Observe any state within the board is return, even if such is a WALL, JUMP, ...
  func getSPrimeWithBounce(fromState: State, takingAction: Action) -> (sprime: State, bounced: Bool) {
    switch (takingAction) {
    case .LEFT:
      if (fromState._col-1) >= 0 {
        return (_maze[fromState._row][fromState._col-1], false)
      }
      return (fromState, true)
    case .RIGHT:
      if (fromState._col+1) < _colCount {
        return (_maze[fromState._row][fromState._col+1], false)
      }
    case .UP:
      if (fromState._row-1) >= 0 {
        return (_maze[fromState._row-1][fromState._col], false)
      }
    case .DOWN:
      if (fromState._row+1) < _rowCount {
        return (_maze[fromState._row+1][fromState._col], false)
      }
    }
    return (fromState, true)  // We're bouncing off an outside border wall
  }
  
  //---
  public func createQTableFromUniform(distributionTotal: Float) -> QTable {
    let qtable = QTable(rowCount: _rowCount, colCount: _colCount)
    
    // Iterate over rows
    for (rowIdx, row) in _maze.enumerated() {
      // Iterate over columns
      for (colIdx, state) in row.enumerated() {
        if state._isEnd {
          qtable[rowIdx, colIdx] = ActionValueList(actionValues: [])  // Empty == terminal
        } else {
          let valueEach = distributionTotal / 4.0
          qtable[rowIdx, colIdx] = ActionValueList(actionValues: [
            ActionValue(a: .LEFT, v: valueEach),
            ActionValue(a: .UP, v: valueEach),
            ActionValue(a: .DOWN, v: valueEach),
            ActionValue(a: .RIGHT, v: valueEach)
          ])
        }
      }
    }
    return qtable
  }
  
  //---
  func createQTableFromVTable(from: VTable) -> QTable {
    precondition(_maze.count == from._vtable.count, "Row count mismatch between maze, vtable")
    
    let qtable = QTable(rowCount: _rowCount, colCount: _colCount)
    
    // Iterate over rows
    for (rowIdx, row) in _maze.enumerated() {
      precondition(_maze[rowIdx].count == from._vtable[rowIdx].count, "Column differs: maze, vtable")
      
      // Iterate over columns
      for (colIdx, state) in row.enumerated() {
        if state._isEnd {
          qtable[rowIdx, colIdx] = ActionValueList(actionValues: [])  // Empty == terminal
        } else {
          let (sLeft, _)  = getSPrimeWithBounce(fromState: state, takingAction: .LEFT)
          let (sUp, _)    = getSPrimeWithBounce(fromState: state, takingAction: .UP)
          let (sDown, _)  = getSPrimeWithBounce(fromState: state, takingAction: .DOWN)
          let (sRight, _) = getSPrimeWithBounce(fromState: state, takingAction: .RIGHT)
          let vLeft  = from[sLeft._row, sLeft._col] + sLeft._reward
          let vUp    = from[sUp._row, sUp._col] + sUp._reward
          let vDown  = from[sDown._row, sDown._col] + sDown._reward
          let vRight = from[sRight._row, sRight._col] + sRight._reward
          qtable[rowIdx, colIdx] = ActionValueList(actionValues: [
            ActionValue(a: .LEFT, v: vLeft),
            ActionValue(a: .UP, v: vUp),
            ActionValue(a: .DOWN, v: vDown),
            ActionValue(a: .RIGHT, v: vRight)
          ])
        }
      }
    }
    return qtable
  }
}

//----
public typealias VTableDefinition = [[Float]]
public class VTable {
  var _rowCount: Int
  var _colCount: Int
  var _vtable: VTableDefinition
  
  //----
  init(rowCount: Int, colCount: Int) {
    _rowCount = rowCount
    _colCount = colCount
    _vtable = Array<Array>(
      repeating: Array<Float>(repeating: 0.0, count: _colCount),
      count: _rowCount)
  }
  
  //----
  init(vtable: VTable) {
    _rowCount = vtable._rowCount
    _colCount = vtable._colCount
    _vtable = vtable._vtable
  }
  
  //---
  subscript(row: Int, col: Int) -> Float {
    get { return _vtable[row][col] }
    set { _vtable[row][col] = newValue }
  }
}

//----
typealias QTableDefinition = [[ActionValueList]]
public class QTable {
  var _mazeEnv: GridMazeEnvironment?  = nil
  var _rowCount: Int
  var _colCount: Int
  var _qtable: QTableDefinition
  
  //----
  init(rowCount: Int, colCount: Int, qtable: QTableDefinition?=nil) {
    _rowCount = rowCount
    _colCount = colCount
    
    if qtable != nil {
      _qtable = qtable!
    } else {
      // Create the array space
      _qtable = QTableDefinition()
      for _ in 0..<_rowCount {
        var rowArray = [ActionValueList]()
        for _ in 0..<_colCount {
          rowArray.append(ActionValueList(actionValues: [ActionValue]()))
        }
        _qtable.append(rowArray)
      }
    }
  }
  
  //----
  init(qtable: QTable) {
    _rowCount = qtable._rowCount
    _colCount = qtable._colCount
    _qtable = qtable._qtable
  }
  
  //---
  public subscript(row: Int, col: Int) -> ActionValueList {
    get { return _qtable[row][col] }
    set { _qtable[row][col] = newValue }
  }
  
  //---
  public subscript(row: Int, col: Int, action: Action) -> ActionValue {
    get {
      let avl = _qtable[row][col]
      return avl[action]
    }
    set { _qtable[row][col][action] = newValue }
  }
  
  //----
  public func getMaxValue(state: State) -> Float {
    if !state._isVisitable {
      return 0
    }
    let maxValue: Float = self[state._row, state._col]._actionValues.max(by: { $0._value < $1._value })!._value
    return maxValue
  }

  //----
  public func getMaxActionValues(state: State, breakTiesArbitrarily: Bool=false) -> [ActionValue] {
    if !state._isVisitable {
      return []
    }
    let maxValue: Float = self[state._row, state._col]._actionValues.max(by: { $0._value < $1._value })!._value
    var maxActionValues = self[state._row, state._col]._actionValues.filter { $0._value == maxValue }
    if breakTiesArbitrarily {
      let indexToPick = Int.random(in: 0..<maxActionValues.count)
      maxActionValues = [maxActionValues[indexToPick]]
    }
    return maxActionValues
  }
  
  //----
  func isActionEquivalent(qtable: QTable) -> Bool {
    if _rowCount != qtable._rowCount || _colCount != qtable._colCount {
      return false
    }
    
    for (ri, r) in _qtable.enumerated() {
      for (ci, av1) in r.enumerated() {
        let av2 = qtable[ri,ci]
        if !av1.isActionEquivalent(compare: av2) {
          return false
        }
      }
    }
    return true
  }
  
  //----
  func normalize2ProbabilityDistribution() -> QTable {
    let rv = QTable(rowCount: _rowCount, colCount: _colCount)
    rv._qtable = _qtable  // Full copy since array of structs
    
    for (ri, r) in rv._qtable.enumerated() {
      for (ci, av) in r.enumerated() {
        rv._qtable[ri][ci] = av.normalize2ProbabilityDistribution()
      }
    }
    
    return rv
  }
  
  //----
  // If breakTiesArbitrarily then it will randomly select a single action if there are >1 equal ones
  // If !breakTiesArbitrarily then ActionValueLists with >1 equal values could be returned
  func reduceToMaxTable(breakTiesArbitrarily: Bool=false,
                        adjustProbabilityTo1: Bool=true) -> QTable {
    
    var nt = _qtable  // Array is value type so this creates copy
    for (ri,r) in nt.enumerated() {
      for (ci,actionValueList) in r.enumerated() {   // actionValueList is struct type
        if actionValueList._actionValues.count > 0 {
          // Find the max probabilities (list.size >1 if multiple have the max probability)
          // Obs, retain the probability rather than changing it to 1
          let avMax = actionValueList._actionValues.max {
            $1._value > $0._value
          }
          var avList = actionValueList._actionValues.filter {
            $0._value == avMax!._value
          }
          // Break ties
          if avList.count > 0 && breakTiesArbitrarily {
            let idx = Int.random(in: 0..<avList.count)
            avList = [avList[idx]]
          }
          // Make remaining actionValues sum to 1.0 probability
          if adjustProbabilityTo1 {
            let part: Float = 1.0 / Float(avList.count)
            avList = avList.map {
              var a = $0
              a._value = part
              return a
            }
          }
          
          nt[ri][ci] = ActionValueList(actionValues: avList)
        }
      }
    }
    return QTable(rowCount: _rowCount, colCount: _colCount, qtable: nt)
  }
}

//----
public struct ActionValueList {
  public var _actionValues = [ActionValue]()  // Empty means a terminal state
  
  var isTerminal: Bool { return _actionValues.count == 0 }
  
  //----
  init (actionValues: [ActionValue]) {
    _actionValues = actionValues
  }
  
  //---
  subscript(index: Int) -> ActionValue {
    get { return _actionValues[index] }
    set { _actionValues[index] = newValue }
  }
  
  //---
  subscript(action: Action) -> ActionValue {
    get {
      let terminal = isTerminal
      precondition(!terminal, "Operation not supported for terminal states")
      if let apidx = _actionValues.firstIndex(where: { $0._action == action }) {
        return _actionValues[apidx]
      }
      precondition(false, "Should never arrive here")
    }
    set {
      precondition(!isTerminal, "Operation not supported for terminal states")
      if let apidx = _actionValues.firstIndex(where: { $0._action == action }) {
        _actionValues[apidx] = newValue
        return
      }
      precondition(false, "Should never arrive here")
    }
  }
  
  //----
  func isActionEquivalent(compare: ActionValueList) -> Bool {
    let s1 = Set(_actionValues.map { $0._action })
    let s2 = Set(compare._actionValues.map { $0._action })
    return s1.symmetricDifference(s2).count == 0
  }
  
  //----
  func normalize2ProbabilityDistribution() -> ActionValueList {
    if isTerminal {
      return ActionValueList(actionValues: [])
    }
    
    let vLeft = self[.LEFT]
    let vUp   = self[.UP]
    let vDown = self[.DOWN]
    let vRight = self[.RIGHT]
    let softmax = getSoftmax(args: [vLeft._value, vUp._value, vDown._value, vRight._value])
    return ActionValueList(actionValues: [
      ActionValue(a: .LEFT, v: softmax[0]),
      ActionValue(a: .UP, v: softmax[1]),
      ActionValue(a: .DOWN, v: softmax[2]),
      ActionValue(a: .RIGHT, v: softmax[3])
    ])
  }
  
  //----
  func getString(printFullFloat: Bool = false) -> String {
    if isTerminal {
      return "*"
    }
    var r = ""
    for (idx,av) in _actionValues.enumerated() {
      r.append(contentsOf: "\(action2Str(action: av._action)):\(float2Str(printFullFloat: printFullFloat, value: av._value))")
      if idx+1 < _actionValues.count {
        r.append(",")
      }
    }
    return r
  }
}

//----
public struct ActionValue {
  public var _value: Float
  public var _action: Action
  
  //----
  init(a: Action, v: Float) {
    _action = a
    _value = v
  }
}

//----
public enum Action: Int, CaseIterable {
  case LEFT
  case UP
  case DOWN
  case RIGHT
}
func action2Str(action: Action) -> String {
  switch action {
  case .LEFT: return "<"
  case .UP: return "A"
  case.DOWN: return "V"
  case .RIGHT: return ">"
  }
}

//----
public typealias JumpSpecificationProbability = (js:JumpSpecification, p:Float)
public enum JumpSpecification: Equatable {
  case Welcome     // I am happy to welcome you to my space
  case BounceBack  // You cannot enter my space, bounce back (e.g. Wall)
  case Relative(Int, Int)  // Teleport (extend to also support a function argument)
  case Absolute(Int, Int)  // Teleport (extend to also support a function argument)
}
func js2String(js: JumpSpecification) -> String {
  switch js {
  case .Welcome: return "Welcome"
  case .BounceBack: return "BounceBack"
  case let .Relative(row, col): return String(format: "Relative (%d,%d)", row,col)
  case let .Absolute(row, col): return String(format: "Absolute (%d,%d)", row,col)
  }
}

//----
public class State {
  var _oneLetterDescription: String
  
  var _mazeEnv: GridMazeEnvironment? = nil
  public var _row = -1
  public var _col = -1
  var _reward: Float = -1
  var _isVisitable = false
  var _isStart = false
  public var _isEnd = false
  
  //----
  init(oneLetterDescription: String,
       reward: Float,
       jumpProbabilities: [JumpSpecificationProbability] = [],
       isVisitable: Bool,  // false if there is no V or Q value for this state (e.g. final state, transponder, etc)
    isStart: Bool,
    isEnd: Bool) {
    _oneLetterDescription = oneLetterDescription
    _reward = reward
    _isVisitable = isVisitable
    _isStart = isStart
    _isEnd = isEnd
    _jumpProbabilities = jumpProbabilities
    setJumpProbabilities(jumpProbabilities: jumpProbabilities)  // Triggers willSet _jump = jump wont do it
  }
  
  // Defines probability and behavior when attempting to enter this state
  var _jumpProbabilities: [JumpSpecificationProbability] {
    willSet {
      let probSum = newValue.reduce(0) { $0 + $1.p }
      guard _jumpProbabilities.count == 0 || probSum == 1.0 else {  // All probabilities must sum to 1.0
        fatalError("Jump probabilities don't sum to 1.0")
      }
    }
  }
  public func setJumpProbabilities(jumpProbabilities: [JumpSpecificationProbability]) {
    _jumpProbabilities = jumpProbabilities
  }
  
  //----
  func is100PercentWelcomingState() -> Bool {
    if _jumpProbabilities.count == 0 {
      return true
    }
    if _jumpProbabilities.count == 1 && _jumpProbabilities[0].js == .Welcome {
      precondition(_jumpProbabilities[0].p == 1, "Single welcome requires 1.0 probability, got: \(_jumpProbabilities[0].p)")
      return true
    }
    return false
  }
  
  //----
  func initialize(mazeEnv: GridMazeEnvironment, row: Int, col: Int) {
    _mazeEnv = mazeEnv
    _row = row
    _col = col
  }
  
  
  
}

// ***************************************************************************

public class SPACE: State {
  public init(reward: Float = -1) {
    // You can omit the jump specification in which case it is Welcome with 1.0 probability
    super.init(oneLetterDescription: "SPACE", reward: reward, jumpProbabilities: [], isVisitable: true, isStart: false, isEnd: false)
  }
}

public class START: State {
  public init(reward: Float = -1) {
    super.init(oneLetterDescription: "START", reward: reward, jumpProbabilities: [], isVisitable: true, isStart: true, isEnd: false)
  }
}

public class END: State {
  public init(reward: Float = -1) {
    super.init(oneLetterDescription: "GOAL", reward: reward, jumpProbabilities: [(p:1.0, js:.Welcome)], isVisitable: false, isStart: false, isEnd: true)
  }
}

public class HOLE: State {
  public init(reward: Float = -100) {
    super.init(oneLetterDescription: "HOLE", reward: reward, jumpProbabilities: [(p:1.0, js:.Welcome)], isVisitable: false, isStart: false, isEnd: true)
  }
}

public class WALL: State {
  public init(reward: Float = -1) {
    super.init(oneLetterDescription: "WALL", reward: reward, jumpProbabilities: [(p:1.0, js:.BounceBack)], isVisitable: false, isStart: false, isEnd: false)
  }
}

public class BOUNCEBACK: State {
  public init(reward: Float = -1) {
    super.init(oneLetterDescription: "WALL", reward: reward, jumpProbabilities: [(p:1.0, js:.BounceBack)], isVisitable: false, isStart: false, isEnd: false)
  }
}



// ***************************************************************************
// Print support functions

//----
public func printMazeAndTable(header: String,
                       mazeEnv: GridMazeEnvironment,
                       mazePrintFullFloat: Bool = false,
                       vtable: VTable?=nil,
                       vtablePrintFullFloat: Bool = false,
                       qtable: QTable?=nil,
                       qtablePrintFullFloat: Bool = false,
                       printPolicy: Bool=false) {
  let maze: GridMazeDefinition = mazeEnv._maze
  
  if header.count > 0 { print(header) }
  
  var transitionProbabilitiesFound = false
  for (ri,r) in maze.enumerated() {
    for (ci,state) in r.enumerated() {
      let jsps: [JumpSpecificationProbability] = state._jumpProbabilities
      if (jsps.count > 0){
        if (jsps.count == 1 && jsps[0].js == JumpSpecification.Welcome) {
          // We don't print a natural transition for the action
          break;
        }
        // Printer header information
        if !transitionProbabilitiesFound {
          print("\nTransition probabilities (non-stochastic transitions are not printed (i.e as expected based on action)")
        }
        
        print("[\(ri),\(ci)]: ", terminator: "")
        for (i,jsp) in jsps.enumerated() {
          if (i > 0) { print("       ", terminator: "") }
          let jsStr = js2String(js: jsp.js)
          print("\(String(format: "Probability: %0.2f", jsp.p)), Type: \(jsStr)")
          transitionProbabilitiesFound = true
        }
      }
    }
  }
  if transitionProbabilitiesFound {
    print()
  }
  
  let mazeStr  = printMazePart(maze: maze, printFullFloat: mazePrintFullFloat)
  let (vtableStr, qtableStr, policyStr) = printTableAndPolicy(
    mazeEnv: mazeEnv,
    vtable: vtable,
    vtablePrintFullFloat: vtablePrintFullFloat,
    qtable: qtable,
    qtablePrintFullFloat: qtablePrintFullFloat,
    printPolicy: printPolicy)
  
  // Print column index
  let colCount = mazeStr[0].count
  var colMaxWidth = 2
  for i in 0..<colCount {
    let maxWidth = getLargestColSize(col: i, maze: mazeStr, vtable: vtableStr, qtable: qtableStr, policy: policyStr)
    if maxWidth > colMaxWidth {
      colMaxWidth = maxWidth
    }
  }
  print("        ", terminator: "")  // This is the row index pre-space
  for i in 0..<colCount {
    print(strCenter(str: String(format: "%02d", i), len: colMaxWidth), terminator: "")
    print("  ", terminator: "")
  }
  print()
  
  // Print all rows with maze, table, and policy
  for (ri,r) in mazeStr.enumerated() {
    // Print row index
    print(String(format: "%02d      ", ri), terminator: "")
    // Print states
    for c in r {
      let ccenter = strCenter(str: c, len: colMaxWidth)
      print("\(ccenter)  ", terminator: "")
    }
    print()
    // Potentially print vtable
    if let vts = vtableStr?[ri] {
      for (ci, c) in vts.enumerated() {
        let ccenter = strCenter(str: c, len: colMaxWidth)
        if (ci == 0) {
          print("VTable  ", terminator: "")
        }
        print("\(ccenter)  ", terminator: "")
      }
      print()
    }
    // Potentially print qtable
    if let qts = qtableStr?[ri] {
      for (ci, c) in qts.enumerated() {
        let ccenter = strCenter(str: c, len: colMaxWidth)
        if (ci == 0) {
          print("QTable  ", terminator: "")
        }
        print("\(ccenter)  ", terminator: "")
      }
      print()
    }
    // Potentially print policy
    if let ps = policyStr?[ri] {
      for (ci, c) in ps.enumerated() {
        let ccenter = strCenter(str: c, len: colMaxWidth)
        if (ci == 0) {
          print("Policy  ", terminator: "")
        }
        print("\(ccenter)  ", terminator: "")
      }
      print()
    }
    print()
  }
}

//---- private
func printMazePart(maze: [[State]], printFullFloat: Bool) -> [[String]] {
  var cells: [[String]] = []
  
  for row in maze {
    var rowStrs = [String]()
    var str = ""
    for state in row {
      str = "\(state._oneLetterDescription):\(float2Str(printFullFloat: printFullFloat, value: state._reward))"
      if state._isEnd {
        str += ":END"
      } else if state._isStart {
        str += ":START"
      }
      rowStrs.append(str)
    }
    cells.append(rowStrs)
  }
  return cells
}

//---- private
func float2Str(printFullFloat: Bool, value: Float) -> String {
  if printFullFloat {
    return String(format: "%f", value)
  }
  if value.truncatingRemainder(dividingBy: 1) == 0 {
    return String(format: "%d", Int(value))
  }
  
  var floatVDec:Float = value
  floatVDec *= 10.0
  if floatVDec.truncatingRemainder(dividingBy: 1) == 0 {
    return String(format: "%0.1f", value)
  }
  
  return String(format: "%0.2f", value)
}

//---- private
func printTableAndPolicy(mazeEnv: GridMazeEnvironment,
                         vtable: VTable?=nil,
                         vtablePrintFullFloat: Bool,
                         qtable: QTable?=nil,
                         qtablePrintFullFloat: Bool,
                         printPolicy: Bool) -> ([[String]]?, [[String]]?, [[String]]?) {
  if vtable == nil && qtable == nil {
    return (nil,nil,nil)
  }
  
  var vtableResult: [[String]]? = nil
  if vtable != nil {
    vtableResult = []
  }
  var qtableResult: [[String]]? = nil
  if qtable != nil {
    qtableResult = []
  }
  var policyQTableTmp: QTable? = nil
  if qtable != nil {
    policyQTableTmp = qtable!
  } else if vtable != nil {
    policyQTableTmp = mazeEnv.createQTableFromVTable(from: vtable!)
  }
  let policyQTable = policyQTableTmp!.reduceToMaxTable()
  var policyResult: [[String]]? = nil
  if printPolicy {
    policyResult = []
  }
  
  for (ri, r) in mazeEnv._maze.enumerated() {
    var vtableStrs = [String]()
    var qtableStrs = [String]()
    var policyStrs = [String]()
    for ci  in 0..<r.count {
      if let q = qtable?[ri, ci] {
        var s = q.getString(printFullFloat: qtablePrintFullFloat)
        if !mazeEnv._maze[ri][ci]._isVisitable {
          s = "*"
        }
        qtableStrs.append(s)
      }
      if let v = vtable?[ri, ci] {
        var s = float2Str(printFullFloat: vtablePrintFullFloat, value: v)
        if !mazeEnv._maze[ri][ci]._isVisitable {
          s = "*"
        }
        vtableStrs.append(s)
      }
      var s = getBestActionStr(actionValueList: policyQTable[ri, ci])
      if !mazeEnv._maze[ri][ci]._isVisitable {
        s = "*"
      }
      policyStrs.append(s)
    }
    if vtable != nil {
      vtableResult?.append(vtableStrs)
    }
    if qtable != nil {
      qtableResult?.append(qtableStrs)
    }
    policyResult?.append(policyStrs)
  }
  if !printPolicy {
    policyResult = nil
  }
  return (vtableResult, qtableResult, policyResult)
}
func getBestActionStr(actionValueList: ActionValueList) -> String {
  if actionValueList.isTerminal { return "*" }
  var result = ""
  var value: Float? = nil
  for (idx,av) in actionValueList._actionValues.enumerated() {
    if value == nil {
      value = av._value
    }
    precondition(value == av._value, "Expected all action values to have same probability: \(actionValueList._actionValues)")
    result += action2Str(action: av._action)
    if idx < actionValueList._actionValues.endIndex-1 {
      result += " "
    }
  }
  return result
}

//---- private
func getLargestColSize(col: Int, maze: [[String]], vtable: [[String]]?, qtable: [[String]]?, policy: [[String]]?) -> Int {
  let mcols = maze.map { $0[col] }
  let vcols = vtable?.map { $0[col] } ?? []
  let qcols = qtable?.map { $0[col] } ?? []
  let pcols = policy?.map { $0[col] } ?? []
  return (mcols+vcols+qcols+pcols).max { $0.count < $1.count }!.count  // at least maze is non-empty
}

// ***************************************************************************
// Convergence/training time analysis

class StopTrainingCondition {
  var _mazeEnv: GridMazeEnvironment
  let _iterationsMax: Int
  var _stopOnConvergence = false
  var _stopOnPercentDiff: Float = 0.0
  var _debug = false
  
  // Variables that needs to be reset after done is reached
  var _iterationsCurrent = 0
  var _qtablePrev: QTable? = nil
  var _vtablePrev: VTable? = nil
  var _sumPrev: Float = 0
  var _isDone = false
  var _doneCause: DoneCause? = nil
  
  //----
  enum DoneCause {
    case CONVERGED
    case DELTAPERCENT
    case ITERATIONCOUNT
  }
  
  //----
  func getTerminationStr() -> String {
    precondition(_isDone, "Expected _isDone but it's not")
    precondition(_doneCause != nil, "_isDone, but no _doneCause set")
    switch _doneCause! {
    case .CONVERGED:
      return "Convergence reached after \(getIterationCount()-1) sweeps (detected while doing sweep \(getIterationCount()))"  // Need 1 iter to detect convergence
    case .DELTAPERCENT:
      return String(format: "Deltapercent reached during sweep: \(getIterationCount()) when delta was <= %.2f",
        _stopOnPercentDiff)
    case .ITERATIONCOUNT:
      return "Maximum sweep count reached: \(getIterationCount())"
    }
  }
  
  //----
  func getIterationCount() -> Int {
    return _iterationsCurrent
  }
  
  func isDone() -> Bool {
    return _isDone
  }
  
  //----
  init(mazeEnv: GridMazeEnvironment,
       iterationsMax: Int,
       stopOnConvergence: Bool = false,
       stopOnPercentDiff: Float = 0.0,
       debug: Bool = false) {
    _mazeEnv = mazeEnv
    _iterationsMax = iterationsMax
    _stopOnConvergence = stopOnConvergence
    _stopOnPercentDiff = stopOnPercentDiff
    _debug = debug
  }
  
  //----
  func reset() {
    _iterationsCurrent = 0
    _qtablePrev = nil
    _vtablePrev = nil
    _sumPrev = 0
    _isDone = false
    _doneCause = nil
  }
  
  //---- Iteration count or vtable convergence is termination criteria
  func reportIteration(vtable: VTable) -> Bool {
    precondition(!_isDone, "A done condition has alread been reported. Illegal to call this method afterwards")
    
    _iterationsCurrent += 1
    
    var qtable = _mazeEnv.createQTableFromVTable(from: vtable)
    qtable = qtable.reduceToMaxTable()  // Equivalence on 2 max tables mean convergence
    
    // First iteration
    if _qtablePrev != nil {
      
      if _debug {
        print("\n********************************************************")
        print("***** StopTrainingCondition: BEGIN DEBUG, iteration: \(getIterationCount()) has been run")
        printMazeAndTable(header: "1. Prev, after iteration: \(getIterationCount() - 1)",
          mazeEnv: _mazeEnv,
          vtable: _vtablePrev!,
          qtable: _qtablePrev!)
        printMazeAndTable(header: "2. Current, after iteration: \(getIterationCount())",
          mazeEnv: _mazeEnv,
          vtable: vtable,
          qtable: qtable)
        // print("Sum of prev: \(_sumPrev), diff to current: \(deltaP), percent increase: \(deltaPercent)")
        print("***** StopTrainingCondition: END DEBUG, iteration: \(getIterationCount()) has been run")
        print("********************************************************\n")
      }
      
      // Did we reach convergence?
      if _qtablePrev!.isActionEquivalent(qtable: qtable) {
        if (_stopOnConvergence) {
          _isDone = true
          _doneCause = .CONVERGED
          return true
        }
      }
      
      // Deduce maximum percent diff for update across all states
      var maxDiffPercent: Float = 0.0
      let fvtablePrev = _vtablePrev!._vtable.flatMap { $0 }
      let fvtableCurr = vtable._vtable.flatMap { $0 }
      for (idx,eprev) in fvtablePrev.enumerated() {
        let ecurr = fvtableCurr[idx]
        let diff = abs(eprev - ecurr)
        let deltaPercent = diff / abs(eprev)
        if deltaPercent > maxDiffPercent {
          maxDiffPercent = deltaPercent
        }
      }
      // Stop if maximum update % was lower than threshold
      if maxDiffPercent <= _stopOnPercentDiff {
        _isDone = true
        _doneCause = .DELTAPERCENT
        return true
      }
    }
    
    // Stop on iteration count?
    if _iterationsCurrent == _iterationsMax {
      _isDone = true
      _doneCause = .ITERATIONCOUNT
      return true
    }
    
    // Move forward
    _qtablePrev = qtable
    _vtablePrev = vtable
    return false
  }
}

// **************************************************************************
// **************************************************************************
// **************************************************************************

//----
func getSoftmax(args: [Float]) -> [Float] {
  let sum = args.reduce(0) { total, num in total + exp(num) }
  return args.map { exp($0) / sum }
}

//----
// TODO: Copyright on StackOverflow code
// From: https://stackoverflow.com/questions/30309556/generate-random-numbers-with-a-given-distribution
// let x = randomNumber(probabilities: [0.2, 0.3, 0.5])
//    returns 0 with probability 0.2, 1 with probability 0.3, and 2 with probability 0.5.
// let x = randomNumber(probabilities: [1.0, 2.0])
//    return 0 with probability 1/3 and 1 with probability 2/3.
public func randomNumber(probabilities: [Float]) -> Int {
  
  // Sum of all probabilities (so that we don't have to require that the sum is 1.0):
  let sum = probabilities.reduce(0, +)
  
  // Random number in the range 0.0 <= rnd < sum :
  let rnd = Float.random(in: 0.0 ..< sum)
  
  // Find the first interval of accumulated probabilities into which `rnd` falls:
  var accum: Float = 0.0
  for (i, p) in probabilities.enumerated() {
    accum += p
    if rnd < accum {
      return i
    }
  }
  
  // This point might be reached due to floating point inaccuracies:
  return (probabilities.count - 1)
}

//----
func strCenter(str: String, len: Int) -> String {
  precondition(len >= str.count, "Cannot center text if it's larger than space")
  var r = str
  let space = len - r.count
  let even = space / 2
  let rem = space % 2
  
  if rem > 0 {
    r = " " + r
  }
  for _ in 0..<even {
    r = " " + r + " "
  }
  return r
}
