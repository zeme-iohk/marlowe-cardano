module Page.Simulation.View where

import Prologue hiding (div)

import Component.BottomPanel.Types as BottomPanelTypes
import Component.BottomPanel.View as BottomPanel
import Component.CurrencyInput (currencyInput)
import Component.DateTimeLocalInput.State as DateTimeLocalInput
import Component.DateTimeLocalInput.Types (Message(..))
import Component.Hint.State (hint)
import Component.Icons as Icon
import Component.Popper (Placement(..))
import Data.Array (concatMap, intercalate, length, reverse, sortWith)
import Data.Array as Array
import Data.Bifunctor (bimap)
import Data.BigInt.Argonaut (BigInt)
import Data.DateTime.Instant (Instant)
import Data.DateTime.Instant as Instant
import Data.Enum (fromEnum)
import Data.Lens (has, only, previewOn, to, view, (^.), (^?))
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.NonEmptyList (_Head)
import Data.Map (Map)
import Data.Map as Map
import Data.Map.Ordered.OMap as OMap
import Data.Maybe (fromMaybe, isJust, maybe)
import Data.Newtype (unwrap)
import Data.Set.Ordered.OSet (OSet)
import Data.String (trim)
import Data.Time.Duration (Minutes, negateDuration)
import Data.Tuple.Nested ((/\))
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen.Classes
  ( aHorizontal
  , bold
  , btn
  , flex
  , flexCol
  , flexGrow
  , flexShrink0
  , fontBold
  , fullHeight
  , fullWidth
  , grid
  , gridColsDescriptionLocation
  , group
  , justifyBetween
  , justifyCenter
  , justifyEnd
  , maxH70p
  , minH0
  , noMargins
  , overflowHidden
  , overflowScroll
  , paddingX
  , plusBtn
  , smallBtn
  , smallSpaceBottom
  , spaceBottom
  , spaceLeft
  , spaceRight
  , spanText
  , spanTextBreakWord
  , textSecondaryColor
  , textXs
  , uppercase
  , w30p
  )
import Halogen.Css (classNames)
import Halogen.Extra (renderSubmodule)
import Halogen.HTML
  ( ClassName(..)
  , ComponentHTML
  , HTML
  , PlainHTML
  , aside
  , b_
  , button
  , div
  , div_
  , em
  , em_
  , h4
  , h6
  , h6_
  , li
  , p
  , p_
  , section
  , slot
  , span
  , span_
  , strong_
  , text
  , ul
  )
import Halogen.HTML.Events (onClick)
import Halogen.HTML.Properties (class_, classes, disabled)
import Halogen.Monaco (monacoComponent)
import Humanize (adjustTimeZone, formatPOSIXTime, humanizeOffset)
import MainFrame.Types
  ( ChildSlots
  , _currencyInputSlot
  , _dateTimeInputSlot
  , _simulatorEditorSlot
  )
import Marlowe.Extended.Metadata (MetaData, NumberFormat(..), getChoiceFormat)
import Marlowe.Monaco as MM
import Marlowe.Semantics
  ( AccountId
  , Assets(..)
  , Bound(..)
  , ChoiceId(..)
  , Input(..)
  , Party(..)
  , Payee(..)
  , Payment(..)
  , TimeInterval(..)
  , Token(..)
  , TransactionInput(..)
  , inBounds
  , timeouts
  )
import Marlowe.Template (TemplateContent(..), orderContentUsingMetadata)
import Marlowe.Time (unixEpoch)
import Monaco as Monaco
import Page.Simulation.BottomPanel (panelContents)
import Page.Simulation.Lenses (_bottomPanelState)
import Page.Simulation.Types (Action(..), BottomPanelView(..), State)
import Plutus.V1.Ledger.Time (POSIXTime(..))
import Pretty
  ( renderPrettyParty
  , renderPrettyPayee
  , renderPrettyToken
  , showPrettyChoice
  , showPrettyMoney
  )
import Simulator.Lenses
  ( _SimulationRunning
  , _currentContract
  , _currentMarloweState
  , _executionState
  , _log
  , _marloweState
  , _possibleActions
  , _time
  , _transactionError
  , _transactionWarnings
  )
import Simulator.State (hasHistory)
import Simulator.Types
  ( ActionInput(..)
  , ActionInputId
  , ExecutionState(..)
  , InitialConditionsRecord
  , LogEntry(..)
  , otherActionsParty
  )
import Text.Markdown.TrimmedInline (markdownToHTML)

render
  :: forall m
   . MonadAff m
  => MetaData
  -> State
  -> ComponentHTML Action ChildSlots m
render metadata state =
  div [ classes [ fullHeight, paddingX, flex ] ]
    [ div [ classes [ flex, flexCol, fullHeight, flexGrow ] ]
        [ section [ classes [ minH0, flexGrow, overflowHidden ] ]
            [ marloweEditor ]
        , section [ classes [ maxH70p ] ]
            [ renderSubmodule
                _bottomPanelState
                BottomPanelAction
                (BottomPanel.render panelTitles wrapBottomPanelContents)
                state
            ]
        ]
    , aside [ classes [ flexShrink0, spaceLeft, overflowScroll, w30p ] ]
        (sidebar metadata state)
    ]
  where
  panelTitles =
    [ { title: "Current State", view: CurrentStateView, classes: [] }
    , { title: problemsTitle, view: WarningsAndErrorsView, classes: [] }
    ]

  runtimeWarnings = view
    ( _marloweState <<< _Head <<< _executionState <<< _SimulationRunning <<<
        _transactionWarnings
    )
    state

  hasRuntimeError :: Boolean
  hasRuntimeError = has
    ( _marloweState <<< _Head <<< _executionState <<< _SimulationRunning
        <<< _transactionError
        <<< to isJust
        <<< only true
    )
    state

  numberOfProblems = length runtimeWarnings + fromEnum hasRuntimeError

  problemsTitle = "Warnings and errors" <>
    if numberOfProblems == 0 then "" else " (" <> show numberOfProblems <> ")"

  -- TODO: improve this wrapper helper
  actionWrapper = BottomPanelTypes.PanelAction

  wrapBottomPanelContents panelView = bimap (map actionWrapper) actionWrapper $
    panelContents metadata state panelView

otherActions :: forall p. HTML p Action
otherActions =
  div [ classes [ group ] ]
    [ editSourceButton ]

{-
    FIXME(outdated): This code was disabled because we changed "source" to "workflow" and
           we move it to the MainFrame. This posses a challenge, were this subcomponent
           needs to see information from the parent state which is not available in the
           subcomponent state.
           There were four possible solutions to this problem:
             * the easy but error prone would be to duplicate state in the MainFrame and here
             * we could change the type of Simulation.State to be
                type State =
                  { ownState :: OwnState -- what we currently call State
                  , parentState :: ProjectedState -- what data from the parent we need in this view, namely workflow
                  }
                or
                type State =
                  { simulationState :: Simulation.OwnState
                  , workflow :: Maybe Workflow
                  }
               which is similar but more "direct", and use a custom lense to provide access to both
               parts of the state.
             * Add the notion of "input" to the subcomponents, similar to what Halogen components do
             * we can reduce functionality and just say "Edit source"
           We opted for the last one as it's the simplest and least conflicting. In January the frontend
           team should meet to discuss the alternatives.
    EDIT: We should just abandon submodules and use regular Components. That will
          allow us to inject the data we need via the input of the component.
    [ sendToBlocklyButton state
      ]
        <> ( if has (_source <<< only Haskell) state then
              [ haskellSourceButton state ]
            else
              []
          )
        <> ( if has (_source <<< only Javascript) state then
              [ javascriptSourceButton state ]
            else
              []
          )
        <> ( if has (_source <<< only Actus) state then
              [ actusSourceButton state ]
            else
              []
          )

sendToBlocklyButton :: forall p. State -> HTML p Action
sendToBlocklyButton state =
  button
    [ onClick $ const $ Just $ SetBlocklyCode
    , enabled isBlocklyEnabled
    , classes [ Classes.disabled (not isBlocklyEnabled) ]
    ]
    [ text "View in Blockly Editor" ]
  where
  isBlocklyEnabled = view (_marloweState <<< _Head <<< _editorErrors <<< to Array.null) state

haskellSourceButton :: forall p. State -> HTML p Action
haskellSourceButton state =
  button
    [ onClick $ const $ Just $ EditHaskell
    ]
    [ text "Edit Haskell Source" ]

javascriptSourceButton :: forall p. State -> HTML p Action
javascriptSourceButton state =
  button
    [ onClick $ const $ Just $ EditJavascript
    ]
    [ text "Edit Javascript Source" ]

actusSourceButton :: forall p. State -> HTML p Action
actusSourceButton state =
  button
    [ onClick $ const $ Just $ EditActus
    ]
    [ text "Edit Actus Source" ]
-}
editSourceButton :: forall p. HTML p Action
editSourceButton =
  button
    [ onClick $ const EditSource
    , classNames [ "btn" ]
    ]
    [ text "Edit source" ]

marloweEditor
  :: forall m
   . MonadAff m
  => ComponentHTML Action ChildSlots m
marloweEditor = slot _simulatorEditorSlot unit component unit
  HandleEditorMessage
  where
  setup editor = liftEffect $ Monaco.setReadOnly editor true

  component = monacoComponent $ MM.settings setup

------------------------------------------------------------
sidebar
  :: forall m
   . MonadAff m
  => MetaData
  -> State
  -> Array (ComponentHTML Action ChildSlots m)
sidebar metadata state =
  case view (_marloweState <<< _Head <<< _executionState) state of
    SimulationNotStarted notStartedRecord ->
      [ startSimulationWidget metadata notStartedRecord state.tzOffset ]
    SimulationRunning _ ->
      [ div [ class_ smallSpaceBottom ] [ simulationStateWidget state ]
      , div [ class_ spaceBottom ] [ actionWidget metadata state ]
      , logWidget metadata state
      ]

------------------------------------------------------------

type TemplateFormDisplayInfo =
  { lookupDefinition ::
      String -> Maybe String -- Gets the definition for a given key
  , title :: String -- Title of the section of the template type
  , orderedMetadataSet ::
      OSet String -- Ordered set of parameters with metadata (in custom metadata order)
  }

startSimulationWidget
  :: forall m
   . MonadAff m
  => MetaData
  -> InitialConditionsRecord
  -> Minutes
  -> ComponentHTML Action ChildSlots m
startSimulationWidget
  metadata
  { initialTime
  , templateContent
  }
  tzOffset =
  cardWidget "Simulation has not started yet"
    $ div_
        [ div
            [ classes [ ClassName "time-input", ClassName "initial-time-input" ]
            ]
            [ spanText "Initial time:"
            , marloweInstantInput "initial-time"
                [ "mx-2", "flex-grow", "flex-shrink-0", "flex", "gap-2" ]
                SetInitialTime
                initialTime
                tzOffset
            ]
        , templateParameters
            metadata
            templateContent
            { valueAction: SetValueTemplateParam
            , timeAction: SetTimeTemplateParam
            }
            tzOffset
        , div [ classNames [ "transaction-btns", "flex", "justify-center" ] ]
            [ button
                [ classNames
                    [ "btn", "bold", "flex-1", "max-w-[15rem]", "mx-2" ]
                , onClick $ const DownloadAsJson
                ]
                [ text "Download as JSON" ]
            , button
                [ classNames
                    [ "btn", "bold", "flex-1", "max-w-[15rem]", "mx-2" ]
                , onClick $ const StartSimulation
                ]
                [ text "Start simulation" ]
            ]
        ]

type TemplateParameterActionsGen action =
  { valueAction :: String -> BigInt -> action
  , timeAction :: String -> Instant -> action
  }

templateParameters
  :: forall action m
   . MonadAff m
  => MetaData
  -> TemplateContent
  -> TemplateParameterActionsGen action
  -> Minutes
  -> ComponentHTML action ChildSlots m
templateParameters
  metadata
  (TemplateContent { timeContent, valueContent })
  { valueAction, timeAction }
  tzOffset =

  let
    inputCss = [ "mx-2", "flex-grow", "flex-shrink-0", "flex", "gap-2" ]
    timeoutParameters = templateParametersSection
      ( \fieldName fieldValue ->
          marloweInstantInput
            (templateFieldRef fieldName)
            inputCss
            (timeAction fieldName)
            fieldValue
            tzOffset
      )
      timeParameterDisplayInfo
      timeContent

    valueParameters = templateParametersSection
      ( \fieldName fieldValue ->
          case extractValueParameterNuberFormat fieldName of
            Just (currencyLabel /\ numDecimals) ->
              marloweCurrencyInput (templateFieldRef fieldName)
                inputCss
                (valueAction fieldName)
                currencyLabel
                numDecimals
                fieldValue
            Nothing -> marloweActionInput (templateFieldRef fieldName)
              inputCss
              (valueAction fieldName)
              fieldValue
      )
      valueParameterDisplayInfo
      valueContent
    lookupDescription k m =
      ( case Map.lookup k m of
          Just { valueParameterDescription: description }
            | trim description /= "" -> Just description
          _ -> Nothing
      )

    timeParameterDisplayInfo =
      { lookupDefinition: (flip Map.lookup)
          (Map.fromFoldableWithIndex metadata.timeParameterDescriptions) -- Convert to normal Map for efficiency
      , title: "Timeout template parameters"
      , orderedMetadataSet: OMap.keys metadata.timeParameterDescriptions
      }

    valueParameterDisplayInfo =
      { lookupDefinition: (flip lookupDescription)
          (Map.fromFoldableWithIndex metadata.valueParameterInfo) -- Convert to normal Map for efficiency
      , title: "Value template parameters"
      , orderedMetadataSet: OMap.keys metadata.valueParameterInfo
      }
    extractValueParameterNuberFormat fieldName =
      case OMap.lookup fieldName metadata.valueParameterInfo of
        Just { valueParameterFormat: DecimalFormat numDecimals currencyLabel } ->
          Just (currencyLabel /\ numDecimals)
        _ -> Nothing
  in
    div_ (timeoutParameters <> valueParameters)

templateFieldRef :: String -> String
templateFieldRef fieldName = "template-parameter-" <> fieldName

emptyDiv :: forall w i. HTML w i
emptyDiv = div_ []

templateParametersSection
  :: forall inputType action m
   . MonadAff m
  => (String -> inputType -> ComponentHTML action ChildSlots m)
  -> TemplateFormDisplayInfo
  -> Map String inputType
  -> Array (ComponentHTML action ChildSlots m)
templateParametersSection
  componentGen
  { lookupDefinition
  , title
  , orderedMetadataSet
  }
  content =
  let
    templateFieldTitle =
      h6 [ classNames [ "italic", "m-0", "mb-4" ] ]
        [ text title ]

    parameterHint fieldName =
      maybe emptyDiv
        ( \explanation ->
            hint
              [ "leading-none" ]
              (templateFieldRef fieldName)
              Auto
              (markdownHintWithTitle fieldName explanation)

        )
        $ lookupDefinition fieldName

    templateParameter (fieldName /\ fieldValue) =
      div
        [ classNames [ "m-2", "ml-6", "flex", "flex-wrap" ] ]
        [ div_
            [ strong_ [ text fieldName ]
            , text ":"
            ]
        , parameterHint fieldName
        , componentGen fieldName fieldValue
        ]
    orderedContent = orderContentUsingMetadata content orderedMetadataSet
  in
    if Map.isEmpty content then
      []
    else
      join
        [ [ templateFieldTitle ]
        , OMap.toUnfoldable orderedContent <#> templateParameter
        ]

------------------------------------------------------------
simulationStateWidget :: forall p. State -> HTML p Action
simulationStateWidget state =
  let
    tzOffset = state.tzOffset
    offsetStr = humanizeOffset tzOffset
    currentTime = state ^.
      ( _currentMarloweState <<< _executionState <<< _SimulationRunning
          <<< _time
          <<< to POSIXTime
          -- TODO SCP-3833 Add type safety to timezone conversions
          <<< to (formatPOSIXTime $ negateDuration tzOffset)
          <<< to \(dateStr /\ timeStr) ->
            intercalate " " [ dateStr, timeStr, offsetStr ]
      )

    expirationTime = contractMaxTime (previewOn state _currentContract)

    contractMaxTime = case _ of
      Nothing -> "Closed"
      Just contract ->
        let
          posixTime = (_.maxTime <<< unwrap <<< timeouts) contract
          -- TODO SCP-3833 Add type safety to timezone conversions
          dateStr /\ timeStr = formatPOSIXTime (negateDuration tzOffset)
            posixTime
        in
          intercalate " " [ dateStr, timeStr, offsetStr ]

    indicator name value =
      div [ classNames [ "flex", "flex-col" ] ]
        [ span
            [ class_ bold ]
            [ text $ name <> ": " ]
        , span_ [ text value ]
        ]
  in
    div
      [ classes [ flex, justifyBetween ] ]
      [ indicator "current time" currentTime
      , indicator "expiration time" expirationTime
      ]

------------------------------------------------------------
actionWidget
  :: forall m
   . MonadAff m
  => MetaData
  -> State
  -> ComponentHTML Action ChildSlots m
actionWidget metadata state =
  cardWidget "Actions"
    $ div [ classes [] ]
        [ ul [ class_ (ClassName "participants") ]
            if (Map.isEmpty possibleActions) then
              [ text "No valid inputs can be added to the transaction" ]
            else
              (actionsForParties possibleActions)
        , div [ classes [ ClassName "transaction-btns", flex, justifyCenter ] ]
            [ button
                [ classes [ btn, bold, spaceRight ]
                , disabled $ not $ hasHistory state
                , onClick $ const Undo
                ]
                [ text "Undo" ]
            , button
                [ classes [ btn, bold ]
                , onClick $ const ResetSimulator
                ]
                [ text "Reset" ]
            ]
        ]
  where
  possibleActions = fromMaybe Map.empty $ state ^? _marloweState <<< _Head
    <<< _executionState
    <<< _SimulationRunning
    <<< _possibleActions
    <<< _Newtype

  kvs :: forall k v. Map k v -> Array (Tuple k v)
  kvs = Map.toUnfoldable

  vs :: forall k v. Map k v -> Array v
  vs m = map snd (kvs m)

  sortParties :: forall v. Array (Tuple Party v) -> Array (Tuple Party v)
  sortParties = sortWith (\(Tuple party _) -> party == otherActionsParty)

  actionsForParties
    :: Map Party (Map ActionInputId ActionInput)
    -> Array (ComponentHTML Action ChildSlots m)
  actionsForParties m = map
    (\(Tuple k v) -> participant metadata state k (vs v))
    (sortParties (kvs m))

participant
  :: forall m
   . MonadAff m
  => MetaData
  -> State
  -> Party
  -> Array ActionInput
  -> ComponentHTML Action ChildSlots m
participant metadata state party actionInputs =
  li [ classes [ noMargins ] ]
    ( [ title ]
        <> (map (inputItem metadata state) actionInputs)
    )
  where
  partyHint = case party of
    Role roleName ->
      maybe emptyDiv
        ( \explanation ->
            hint
              [ "relative", "-top-1" ]
              ("participant-hint-" <> roleName)
              Auto
              (markdownHintWithTitle roleName explanation)
        )
        $ Map.lookup roleName metadata.roleDescriptions
    _ -> emptyDiv

  title =
    div [ classes [ ClassName "action-group" ] ]
      if party == otherActionsParty then
        -- QUESTION: if we only have "move to time", could we rename this to "Time Actions"?
        [ h6_ [ em_ [ text "Other Actions" ] ] ]
      else
        [ h6_
            [ em [ classNames [ "mr-1" ] ]
                [ text "Participant "
                , strong_ [ text partyName ]
                ]
            , partyHint
            ]
        ]

  partyName = case party of
    (PK name) -> name
    (Role name) -> name

inputItem
  :: forall m
   . MonadAff m
  => MetaData
  -> State
  -> ActionInput
  -> ComponentHTML Action ChildSlots m
inputItem metadata _ (DepositInput accountId party token value) =
  div [ classes [ ClassName "action", aHorizontal ] ]
    [ renderDeposit metadata accountId party token value
    , div [ class_ (ClassName "align-top") ]
        [ button
            [ classes [ plusBtn, smallBtn, btn ]
            , onClick $ const $ AddInput (IDeposit accountId party token value)
                []
            ]
            [ text "+" ]
        ]
    ]

inputItem
  metadata
  _
  (ChoiceInput choiceId@(ChoiceId choiceName choiceOwner) bounds chosenNum) =
  let
    ref = "choice-hint-" <> choiceName

    choiceHint =
      maybe (div_ [])
        ( \explanation ->
            hint
              [ "relative", "-top-1" ]
              ref
              Auto
              (markdownHintWithTitle choiceName explanation)
        )
        (mChoiceInfo >>= mExtractDescription)
  in
    div
      [ classes [ ClassName "action", aHorizontal, ClassName "flex-nowrap" ] ]
      ( [ div [ classes [ ClassName "action-label" ] ]
            [ div [ class_ (ClassName "choice-input") ]
                [ span [ class_ (ClassName "break-word-span") ]
                    [ text "Choice "
                    , b_ [ text (show choiceName <> ": ") ]
                    , choiceHint
                    ]
                , case mChoiceInfo of
                    Just
                      { choiceFormat: DecimalFormat numDecimals currencyLabel } ->
                      marloweCurrencyInput ref
                        [ "mx-2", "flex-grow", "flex-shrink-0" ]
                        (SetChoice choiceId)
                        currencyLabel
                        numDecimals
                        chosenNum
                    _ -> marloweActionInput ref
                      [ "mx-2", "flex-grow", "flex-shrink-0" ]
                      (SetChoice choiceId)
                      chosenNum
                ]
            , div [ class_ (ClassName "choice-error") ] error
            ]
        ]
          <> addButton
      )
  where
  mChoiceInfo = Map.lookup choiceName metadata.choiceInfo

  mExtractDescription { choiceDescription }
    | trim choiceDescription /= "" = Just choiceDescription

  mExtractDescription _ = Nothing

  addButton =
    if inBounds chosenNum bounds then
      [ button
          [ classes
              [ btn
              , plusBtn
              , smallBtn
              , ClassName "align-top"
              , ClassName "flex-noshrink"
              ]
          , onClick $ const $ AddInput
              (IChoice (ChoiceId choiceName choiceOwner) chosenNum)
              bounds
          ]
          [ text "+" ]
      ]
    else
      []

  error = if inBounds chosenNum bounds then [] else [ text boundsError ]

  boundsError =
    if Array.null bounds then
      "A choice must have set bounds, please fix the contract"
    else
      "Choice must be between " <> intercalate " or " (map boundError bounds)

  boundError (Bound from to) = showPretty from <> " and " <> showPretty to

  showPretty :: BigInt -> String
  showPretty = showPrettyChoice (getChoiceFormat metadata choiceName)

inputItem _ _ NotifyInput =
  li
    [ classes [ ClassName "action", ClassName "choice-a", aHorizontal ] ]
    [ p_ [ text "Notify Contract" ]
    , button
        [ classes [ btn, plusBtn, smallBtn, ClassName "align-top" ]
        , onClick $ const $ AddInput INotify []
        ]
        [ text "+" ]
    ]

inputItem _ state (MoveToTime time) =
  div
    [ classes [ aHorizontal, ClassName "flex-nowrap" ] ]
    ( [ div [ classes [ ClassName "action" ] ]
          [ p [ class_ (ClassName "time-input") ]
              [ spanTextBreakWord "Move current time to"
              , marloweInstantInput "move-to-instant"
                  [ "mx-2", "flex-grow", "flex-shrink-0", "flex", "gap-2" ]
                  SetTime
                  time
                  state.tzOffset
              ]
          , p [ class_ (ClassName "choice-error") ] error
          ]
      ]
        <> addButton
    )
  where
  currentTime = fromMaybe unixEpoch $ state ^?
    _currentMarloweState <<< _executionState <<< _SimulationRunning <<< _time

  isForward = currentTime < time

  addButton =
    if isForward then
      [ button
          [ classes
              [ plusBtn
              , smallBtn
              , ClassName "align-top"
              , ClassName "flex-noshrink"
              , btn
              ]
          , onClick $ const $ MoveTime time
          ]
          [ text "+" ]
      ]
    else
      []

  error = if isForward then [] else [ text boundsError ]

  boundsError = "The new time must be more than the current time."

marloweCurrencyInput
  :: forall m action
   . String
  -> Array String
  -> (BigInt -> action)
  -> String
  -> Int
  -> BigInt
  -> ComponentHTML action ChildSlots m
marloweCurrencyInput ref classList f currencyLabel numDecimals value =
  slot
    _currencyInputSlot
    ref
    currencyInput
    { classList, value, prefix: currencyLabel, numDecimals }
    f

-- This component builds on top of the DateTimeLocal component to work
-- with Instant and to do the UTC convertion. Value in and out are expressed
-- in UTC.
marloweInstantInput
  :: forall m action
   . String
  -> Array String
  -> (Instant -> action)
  -> Instant
  -> Minutes
  -> ComponentHTML action ChildSlots m
marloweInstantInput ref classList f current tzOffset =
  div [ classNames classList ]
    [ slot
        _dateTimeInputSlot
        ref
        DateTimeLocalInput.component
        { classList: [ "flex-grow" ]
        -- TODO: SCP-3833 Add type safety to timezone conversions
        , value: adjustTimeZone (negateDuration tzOffset) $
            Instant.toDateTime current
        , trimSeconds: true
        }
        ( \(ValueChanged dt) -> f $ Instant.fromDateTime $ adjustTimeZone
            tzOffset
            dt
        )
    , text $ humanizeOffset tzOffset
    ]

marloweActionInput
  :: forall m action
   . String
  -> Array String
  -> (BigInt -> action)
  -> BigInt
  -> ComponentHTML action ChildSlots m
marloweActionInput ref classes f current = marloweCurrencyInput ref classes f ""
  0
  current

renderDeposit
  :: forall p
   . MetaData
  -> AccountId
  -> Party
  -> Token
  -> BigInt
  -> HTML p Action
renderDeposit metadata accountOwner party tok money =
  span [ classes [ ClassName "break-word-span" ] ]
    [ text "Deposit "
    , strong_ [ text (showPrettyMoney money) ]
    , text " units of "
    , strong_ [ renderPrettyToken tok ]
    , text " into account of "
    , strong_ [ renderPrettyParty metadata accountOwner ]
    , text " as "
    , strong_ [ renderPrettyParty metadata party ]
    ]

------------------------------------------------------------
logWidget
  :: forall p
   . MetaData
  -> State
  -> HTML p Action
logWidget metadata state =
  cardWidget "Transaction log"
    $ div [ classes [ grid, gridColsDescriptionLocation, fullWidth ] ]
        ( [ div [ class_ fontBold ] [ text "Action" ]
          , div [ class_ fontBold ] [ text "POSIX time" ]
          ]
            <> inputLines
        )
  where
  inputLines = state ^.
    ( _marloweState <<< _Head <<< _executionState <<< _SimulationRunning
        <<< _log
        <<< to (concatMap (logToLines metadata) <<< reverse)
    )

logToLines :: forall p a. MetaData -> LogEntry -> Array (HTML p a)
logToLines _ (StartEvent time) =
  [ span_ [ text "Contract started" ]
  , span [ class_ justifyEnd ] [ text $ show time ]
  ]

logToLines metadata (InputEvent (TransactionInput { interval, inputs })) =
  inputToLine metadata interval =<< Array.fromFoldable inputs

logToLines metadata (OutputEvent interval payment) = paymentToLines metadata
  interval
  payment

logToLines _ (CloseEvent (TimeInterval start end)) =
  [ span_ [ text $ "Contract ended" ]
  , span [ class_ justifyEnd ] [ text $ showTimeRange start end ]
  ]

inputToLine :: forall p a. MetaData -> TimeInterval -> Input -> Array (HTML p a)
inputToLine
  metadata
  (TimeInterval start end)
  (IDeposit accountOwner party token money) =
  [ span_
      [ text "Deposit "
      , strong_ [ text (showPrettyMoney money) ]
      , text " units of "
      , strong_ [ renderPrettyToken token ]
      , text " into account of "
      , strong_ [ renderPrettyParty metadata accountOwner ]
      , text " as "
      , strong_ [ renderPrettyParty metadata party ]
      ]
  , span [ class_ justifyEnd ] [ text $ showTimeRange start end ]
  ]

inputToLine
  metadata
  (TimeInterval start end)
  (IChoice (ChoiceId choiceName choiceOwner) chosenNum) =
  [ span_
      [ text "Participant "
      , strong_ [ renderPrettyParty metadata choiceOwner ]
      , text " chooses the value "
      , strong_
          [ text
              (showPrettyChoice (getChoiceFormat metadata choiceName) chosenNum)
          ]
      , text " for choice with id "
      , strong_ [ text (show choiceName) ]
      ]
  , span [ class_ justifyEnd ] [ text $ showTimeRange start end ]
  ]

inputToLine _ (TimeInterval start end) INotify =
  [ text "Notify"
  , span [ class_ justifyEnd ] [ text $ showTimeRange start end ]
  ]

paymentToLines
  :: forall p a. MetaData -> TimeInterval -> Payment -> Array (HTML p a)
paymentToLines metadata timeInterval (Payment accountId payee money) = join $
  unfoldAssets money (paymentToLine metadata timeInterval accountId payee)

paymentToLine
  :: forall p a
   . MetaData
  -> TimeInterval
  -> AccountId
  -> Payee
  -> Token
  -> BigInt
  -> Array (HTML p a)
paymentToLine metadata (TimeInterval start end) accountId payee token money =
  [ span_
      [ text "The contract pays "
      , strong_ [ text (showPrettyMoney money) ]
      , text " units of "
      , strong_ [ renderPrettyToken token ]
      , text " to "
      , strong_ $ renderPrettyPayee metadata payee
      , text " from "
      , strong_ $ renderPrettyPayee metadata (Account accountId)
      ]
  , span [ class_ justifyEnd ] [ text $ showTimeRange start end ]
  ]

showTimeRange :: POSIXTime -> POSIXTime -> String
showTimeRange start end =
  if start == end then
    show start
  else
    (show start) <> " - " <> (show end)

unfoldAssets :: forall a. Assets -> (Token -> BigInt -> a) -> Array a
unfoldAssets (Assets mon) f =
  concatMap
    ( \(Tuple currencySymbol tokenMap) ->
        ( map
            ( \(Tuple tokenName value) ->
                f (Token currencySymbol tokenName) value
            )
            (Map.toUnfoldable tokenMap)
        )
    )
    (Map.toUnfoldable mon)

------------------------------------------------------------
cardWidget :: forall p a. String -> HTML p a -> HTML p a
cardWidget name body =
  let
    title' = h6
      [ classes [ noMargins, textSecondaryColor, bold, uppercase, textXs ] ]
      [ text name ]
  in
    div [ classes [ ClassName "simulation-card-widget" ] ]
      [ div [ class_ (ClassName "simulation-card-widget-header") ] [ title' ]
      , div [ class_ (ClassName "simulation-card-widget-body") ] [ body ]
      ]

markdownHintWithTitle :: String -> String -> PlainHTML
markdownHintWithTitle title markdown =
  div_
    $
      [ h4
          -- With min-w-max we define that the title should never break into
          -- a different line.
          [ classNames
              [ "no-margins"
              , "text-lg"
              , "font-semibold"
              , "flex"
              , "items-center"
              , "pb-2"
              , "min-w-max"
              ]
          ]
          [ Icon.icon Icon.HelpOutline [ "mr-1", "font-normal" ]
          , text title
          ]
      ]
        <> markdownToHTML markdown
