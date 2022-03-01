module MainFrame.Lenses where

import Prologue

import Data.AddressBook (AddressBook)
import Data.DateTime.Instant (Instant)
import Data.Lens (Lens')
import Data.Lens.AffineTraversal (AffineTraversal')
import Data.Lens.Prism.Either (_Left, _Right)
import Data.Lens.Record (prop)
import Data.Time.Duration (Minutes)
import MainFrame.Types (Slice, State, WebSocketStatus)
import Page.Dashboard.Types (State) as Dashboard
import Page.Welcome.Types (State) as Welcome
import Type.Proxy (Proxy(..))

_webSocketStatus :: Lens' State WebSocketStatus
_webSocketStatus = prop (Proxy :: _ "webSocketStatus")

_currentTime :: Lens' State Instant
_currentTime = _store <<< prop (Proxy :: _ "currentTime")

_addressBook :: Lens' State AddressBook
_addressBook = _store <<< prop (Proxy :: _ "addressBook")

_tzOffset :: Lens' State Minutes
_tzOffset = prop (Proxy :: _ "tzOffset")

_subState :: Lens' State (Either Welcome.State Dashboard.State)
_subState = prop (Proxy :: _ "subState")

_store :: Lens' State Slice
_store = prop (Proxy :: _ "store")

_welcomeState :: AffineTraversal' State Welcome.State
_welcomeState = _subState <<< _Left

_dashboardState :: AffineTraversal' State Dashboard.State
_dashboardState = _subState <<< _Right
