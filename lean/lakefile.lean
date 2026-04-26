import Lake
open Lake DSL

package interactionSystem where
  srcDir := "."

lean_lib LassoMapping where
  roots := #[`LassoMapping]
