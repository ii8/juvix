module Juvix.Compiler.Internal.Pretty
  ( module Juvix.Compiler.Internal.Pretty,
    module Juvix.Compiler.Internal.Pretty.Base,
    module Juvix.Compiler.Internal.Pretty.Options,
    module Juvix.Data.PPOutput,
  )
where

import Juvix.Compiler.Internal.Pretty.Base
import Juvix.Compiler.Internal.Pretty.Options
import Juvix.Data.PPOutput
import Juvix.Prelude
import Prettyprinter.Render.Terminal qualified as Ansi

ppOutDefault :: PrettyCode c => c -> AnsiText
ppOutDefault = AnsiText . PPOutput . doc defaultOptions

ppOut :: (CanonicalProjection a Options, PrettyCode c) => a -> c -> AnsiText
ppOut o = AnsiText . PPOutput . doc (project o)

ppTrace :: PrettyCode c => c -> Text
ppTrace = Ansi.renderStrict . reAnnotateS stylize . layoutPretty defaultLayoutOptions . doc traceOptions
