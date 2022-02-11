-- This module helps you work with slots and DateTimes. We only care about the current slot algorithm
-- that was introduced when Shelley was launched in mid 2020. Since the launch, each slot number
-- corresponds to a second.
module Marlowe.Slot
  ( shelleyInitialSlot
  , slotToDateTime
  , dateTimeToSlot
  , dateTimeStringToSlot
  , posixTimeToSlot
  , slotToPOSIXTime
  , posixTimeToDateTime
  , secondsDiff
  , shelleyLaunchPOSIXTime
  , secondsSinceShelley
  ) where

import Prelude

import Data.BigInt.Argonaut (BigInt, fromInt, fromNumber)
import Data.BigInt.Argonaut as BigInt
import Data.DateTime (DateTime, adjust, diff)
import Data.DateTime.Instant (fromDateTime, instant, toDateTime, unInstant)
import Data.Either (Either(..))
import Data.Formatter.DateTime (Formatter, FormatterCommand(..), unformat) as FDT
import Data.Int (round)
import Data.List (fromFoldable)
import Data.Maybe (Maybe(..), fromJust)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..), Seconds(..))
import Marlowe.Semantics (Slot(..))
import Partial.Unsafe (unsafePartial)
import Plutus.V1.Ledger.Time (POSIXTime(..))

-- TODO: When we are integrated with the real Cardano node, we will need to
-- know the datetime of one slot so that we can convert slots to and from
-- datetimes. Any slot will do, but to avoid arbitrariness it would be nice
-- to know the exact datetime of the Shelley launch, and the slot number at
-- that moment. In the meantime, these are our best guesses based on some
-- quick Googling.  :)
shelleyInitialSlot :: Slot
shelleyInitialSlot = Slot $ fromInt 0

-- Note [Datetime to slot]: The `plutus-pab.yaml` config file can specify
-- the datetime of slot zero. To synchronise with the frontend, this should
-- be set to `shelleyLaunchDate - (shelleyInitialSlot * 1000)` (because there
-- is 1 slot per second). On the current estimates this comes to 1596059091000,
-- which is 2020-07-29 21:44:51 UTC.
shelleyLaunchDate :: DateTime
shelleyLaunchDate =
  let
    -- 2020-07-29 21:44:51 UTC expressed as unix epoch
    epoch = Milliseconds 1596059091000.0
  in
    unsafePartial $ fromJust $ toDateTime <$> instant epoch

shelleyLaunchPOSIXTime :: POSIXTime
shelleyLaunchPOSIXTime = dateTimeToPOSIXTime shelleyLaunchDate

secondsSinceShelley :: Int -> BigInt
secondsSinceShelley i =
  ((unwrap shelleyLaunchPOSIXTime).getPOSIXTime + BigInt.fromInt (i * 1000))

secondsDiff :: Slot -> Slot -> Seconds
secondsDiff a b = Seconds $ BigInt.toNumber $ unwrap $ a - b

posixTimeToSlot :: POSIXTime -> Slot
posixTimeToSlot = dateTimeToSlot <<< posixTimeToDateTime

slotToPOSIXTime :: Slot -> POSIXTime
slotToPOSIXTime s =
  let
    a = unsafePartial $ fromJust $ slotToDateTime s
  in
    dateTimeToPOSIXTime a

posixTimeToDateTime :: POSIXTime -> DateTime
posixTimeToDateTime (POSIXTime t) = unsafePartial $ fromJust $ toDateTime <$>
  instant (Milliseconds (BigInt.toNumber t.getPOSIXTime))

dateTimeToPOSIXTime :: DateTime -> POSIXTime
dateTimeToPOSIXTime dt =
  let
    a :: BigInt
    a = unsafePartial $
      (fromJust <<< fromNumber <<< unwrap <<< unInstant <<< fromDateTime $ dt)
  in
    POSIXTime { getPOSIXTime: a }

slotToDateTime :: Slot -> Maybe DateTime
slotToDateTime slot =
  let
    secondsDiff' = secondsDiff slot shelleyInitialSlot
  in
    adjust secondsDiff' shelleyLaunchDate

dateTimeToSlot :: DateTime -> Slot
dateTimeToSlot datetime =
  let
    secondsDiff' :: Seconds
    secondsDiff' = diff datetime shelleyLaunchDate
  in
    shelleyInitialSlot + (Slot $ BigInt.fromInt $ round $ unwrap secondsDiff')

dateTimeStringToSlot :: String -> Maybe Slot
dateTimeStringToSlot dateTimeString =
  let
    -- this is the format dateTimeStrings appear in an input[type="datetime-local"].value
    dateTimeFormat :: FDT.Formatter
    dateTimeFormat =
      fromFoldable
        [ FDT.YearAbsolute
        , FDT.Placeholder "-"
        , FDT.MonthTwoDigits
        , FDT.Placeholder "-"
        , FDT.DayOfMonthTwoDigits
        , FDT.Placeholder "T"
        , FDT.Hours24
        , FDT.Placeholder ":"
        , FDT.MinutesTwoDigits
        ]
  in
    case FDT.unformat dateTimeFormat dateTimeString of
      Right dateTime -> Just $ dateTimeToSlot dateTime
      Left _ -> Nothing
