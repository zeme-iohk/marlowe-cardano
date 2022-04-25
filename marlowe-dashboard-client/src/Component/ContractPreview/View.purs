module Component.ContractPreview.View
  ( contractPreviewCard
  , contractStartingPreviewCard
  ) where

import Prologue hiding (div)

import Capability.Marlowe (CreateError(..))
import Component.Contract.View (startingStepActions, timeoutString)
import Component.CurrentStepActions.State as CurrentStepActions
import Component.CurrentStepActions.Types (Msg(..), _currentStepActions)
import Component.Icons (Icon(..)) as Icon
import Component.Icons (icon)
import Component.Progress.Circular as Progress
import DOM.HTML.Indexed (HTMLli)
import Data.ContractNickname as ContractNickname
import Data.ContractStatus (ContractStatus(..), ContractStatusId)
import Data.DateTime.Instant (Instant)
import Data.Lens (view, (^.))
import Data.Maybe (maybe)
import Data.NewContract (NewContract(..))
import Data.Newtype (unwrap)
import Data.UUID.Argonaut as UUID
import Effect.Aff.Class (class MonadAff)
import Errors.Explain (explain)
import Halogen (AttrName(..), ComponentHTML)
import Halogen.Css (classNames)
import Halogen.HTML (a, attr, div, h3, h3_, li, p, p_, slot, text)
import Halogen.HTML as HH
import Halogen.HTML.Events.Extra (onClick_)
import Halogen.HTML.Properties (IProp, title)
import Halogen.HTML.Properties.ARIA (role)
import Halogen.Store.Monad (class MonadStore)
import Images (contractIcon)
import Marlowe.Execution.State (currentStep)
import Marlowe.Extended.Metadata (MetaData)
import Marlowe.Semantics (_rolesCurrency)
import Page.Contract.Lenses (_marloweParams, _metadata)
import Page.Dashboard.Types (Action(..), ChildSlots, ContractState)
import Store as Store

-- This card shows a preview of synced contracts (intended to be used in the dashboard)
contractPreviewCard
  :: forall m
   . MonadAff m
  => MonadStore Store.Action Store.Store m
  => Instant
  -> ContractState
  -> ComponentHTML Action ChildSlots m
contractPreviewCard currentTime { executionState, namedActions, nickname } =
  let
    metadata = executionState ^. _metadata
    marloweParams = executionState ^. _marloweParams
    stepPanelChildren =
      [ p
          [ classNames [ "flex-1", "text-sm", "font-semibold" ] ]
          [ text $ "Current step:" <> show (currentStep executionState + 1) ]
      , p
          [ classNames [ "font-semibold" ] ]
          [ text $ timeoutString currentTime executionState ]
      , icon Icon.Timer []
      ]
    stepActions = slot
      _currentStepActions
      marloweParams
      CurrentStepActions.component
      { executionState, namedActions }
      case _ of
        ActionSelected action num ->
          OnAskContractActionConfirmation marloweParams action num
  in
    mkContractCard
      { index: Started marloweParams
      , metadata
      , nickname
      , extraAttrs:
          [ attr (AttrName "data-follower-id")
              $ UUID.toString
              $ unwrap
              $ executionState.followerAppId
          , attr (AttrName "data-currency-id") $ view
              _rolesCurrency
              executionState.marloweParams
          ]
      , stepPanelChildren
      , stepActions
      }

contractStartingPreviewCard
  :: forall m. MonadAff m => NewContract -> ComponentHTML Action ChildSlots m
contractStartingPreviewCard = HH.lazy \newContract ->
  let
    NewContract reqId contractNickname metadata mError _ = newContract
    stepPanelChildren =
      [ p
          [ classNames
              [ "text-sm"
              , "font-semibold"
              , case mError of
                  Nothing -> "text-black"
                  _ -> "text-red"
              ]
          ]
          [ text $ case mError of
              Nothing -> "Starting contract…"
              _ -> "Failed to start contract"
          ]
      , case mError of
          Nothing -> Progress.view Progress.defaultSpec
          _ -> icon Icon.ErrorOutline [ "text-red" ]
      ]
    startingStepActionsFailed error =
      div [ classNames [ "space-y-6" ] ]
        [ h3_ [ text "Message:" ]
        , p_ [ text $ show $ explain $ CreateError error ]
        ]
  in
    mkContractCard
      { index: Starting reqId
      , metadata
      , nickname: ContractNickname.toString contractNickname
      , extraAttrs:
          [ attr (AttrName "data-request-id") $ UUID.toString $ reqId
          , role case mError of
              Nothing -> "listitem"
              _ -> "alert"
          ]
      , stepPanelChildren
      , stepActions: maybe startingStepActions startingStepActionsFailed mError
      }

type ContractCardOptions m =
  { index :: ContractStatusId
  , metadata :: MetaData
  , nickname :: String
  , extraAttrs :: Array (IProp HTMLli Action)
  , stepPanelChildren :: Array (ComponentHTML Action ChildSlots m)
  , stepActions :: ComponentHTML Action ChildSlots m
  }

mkContractCard
  :: forall m. ContractCardOptions m -> ComponentHTML Action ChildSlots m
mkContractCard
  { index, metadata, nickname, extraAttrs, stepPanelChildren, stepActions } =
  let
    { contractType, contractName } = metadata
    liClasses = [ "shadow", "bg-white", "rounded", "divide-y", "divide-gray" ]
  in
    li
      ([ title nickname, classNames liClasses ] <> extraAttrs)
      [ div
          [ classNames [ "flex", "gap-2", "px-4", "py-2" ] ]
          [ div
              [ classNames [ "flex-1", "truncate" ] ]
              [ h3
                  [ classNames [ "flex", "gap-2", "items-center" ] ]
                  [ contractIcon contractType
                  , text contractName
                  ]
              -- FIXME-3562: Make an input again
              , text nickname
              -- , input
              --     [ classNames $ Css.inputNoBorder <> [ "-ml-2", "text-lg" ]
              --     , type_ InputText
              --     , value nickname
              --     , onValueInput_
              --         ( SetNickname <<< fromRight ContractNickname.unknown <<<
              --             ContractNickname.fromString
              --         )
              --     , placeholder "Please rename"
              --     ]
              ]
          , a
              [ classNames [ "flex", "items-center" ]
              , onClick_ $ SelectContract $ Just index
              ]
              [ icon Icon.ArrowRight [ "text-28px" ] ]
          ]
      , div
          [ classNames
              [ "px-4"
              , "py-2"
              , "flex"
              , "items-center"
              , "justify-between"
              , "gap-2"
              ]
          ]
          stepPanelChildren
      , div
          [ classNames [ "h-dashboard-card-actions", "overflow-y-auto", "p-4" ]
          ]
          [ stepActions
          ]
      ]
