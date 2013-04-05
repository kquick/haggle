{-# LANGUAGE KindSignatures, TypeFamilies #-}
module Data.Graph.Haggle.Interface (
  -- * Basic Types
  Vertex,
  Edge,
  -- * Mutable Graphs
  MGraph(..),
  MAddEdge(..),
  MAddVertex(..),
  MRemovable(..),
  MBidirectional(..),
  MLabeledEdge(..),
  MLabeledVertex(..),
  -- * Immutable Graphs
  Graph(..),
  Bidirectional(..),
  HasEdgeLabel(..),
  HasVertexLabel(..)
  ) where

import Control.Monad.Primitive
import Data.Graph.Haggle.Internal.Basic

-- FIXME: Split out addVertex and addEdge so that the mutable graph wrappers
-- can implement the rest of the functions (so there can be graph algorithm
-- implementations for mutable graphs).  This is relatively lower priority.
--
-- Perhaps have a separate class for each of addEdge and addVertex, that way
-- the VertexLabeledMGraph can have addEdge.

-- | The interface supported by a mutable graph.
class MGraph (g :: (* -> *) -> *) where
  -- | The type generated by 'freeze'ing a mutable graph
  type ImmutableGraph g :: *

  -- | List the successors for the given 'Vertex'.
  getSuccessors :: (PrimMonad m) => g m -> Vertex -> m [Vertex]

  -- | Get all of the 'Edge's with the given 'Vertex' as their source.
  getOutEdges :: (PrimMonad m) => g m -> Vertex -> m [Edge]

  -- | Return the number of vertices in the graph
  countVertices :: (PrimMonad m) => g m -> m Int

  -- | Return the number of edges in the graph
  countEdges :: (PrimMonad m) => g m -> m Int

  -- | Edge existence test; this has a default implementation,
  -- but can be overridden if an implementation can support a
  -- better-than-linear version.
  checkEdgeExists :: (PrimMonad m) => g m -> Vertex -> Vertex -> m Bool
  checkEdgeExists g src dst = do
    succs <- getSuccessors g src
    return $ any (==dst) succs

  -- | Freeze the mutable graph into an immutable graph.
  freeze :: (PrimMonad m) => g m -> m (ImmutableGraph g)

class (MGraph g) => MAddVertex (g :: (* -> *) -> *) where
  -- | Add a new 'Vertex' to the graph, returning its handle.
  addVertex :: (PrimMonad m) => g m -> m Vertex

class (MGraph g) => MAddEdge (g :: (* -> *) -> *) where
  -- | Add a new 'Edge' to the graph from @src@ to @dst@.  If either
  -- the source or destination is not in the graph, returns Nothing.
  -- Otherwise, the 'Edge' reference is returned.
  addEdge :: (PrimMonad m) => g m -> Vertex -> Vertex -> m (Maybe Edge)

class (MGraph g) => MLabeledEdge (g :: (* -> *) -> *) where
  type MEdgeLabel g
  getEdgeLabel :: (PrimMonad m) => g m -> Edge -> m (Maybe (MEdgeLabel g))
  addLabeledEdge :: (PrimMonad m) => g m -> Vertex -> Vertex -> MEdgeLabel g -> m (Maybe Edge)

class (MGraph g) => MLabeledVertex (g :: (* -> *) -> *) where
  type MVertexLabel g
  getVertexLabel :: (PrimMonad m) => g m -> Vertex -> m (Maybe (MVertexLabel g))
  addLabeledVertex :: (PrimMonad m) => g m -> MVertexLabel g -> m Vertex

-- | An interface for graphs that allow vertex and edge removal.  Note that
-- implementations are not required to reclaim storage from removed
-- vertices (just make them inaccessible).
class (MGraph g) => MRemovable g where
  removeVertex :: (PrimMonad m) => g m -> Vertex -> m ()
  removeEdgesBetween :: (PrimMonad m) => g m -> Vertex -> Vertex -> m ()
  removeEdge :: (PrimMonad m) => g m -> Edge -> m ()

-- | An interface for graphs that support looking at predecessor (incoming
-- edges) efficiently.
class (MGraph g) => MBidirectional g where
  getPredecessors :: (PrimMonad m) => g m -> Vertex -> m [Vertex]
  getInEdges :: (PrimMonad m) => g m -> Vertex -> m [Edge]

-- | The basic interface of immutable graphs.
class Graph g where
  type MutableGraph g :: (* -> *) -> *
  vertices :: g -> [Vertex]
  edges :: g -> [Edge]
  successors :: g -> Vertex -> [Vertex]
  outEdges :: g -> Vertex -> [Edge]
  edgeExists :: g -> Vertex -> Vertex -> Bool
  thaw :: (PrimMonad m) => g -> m (MutableGraph g m)

-- | The interface for immutable graphs with efficient access to
-- incoming edges.
class (Graph g) => Bidirectional g where
  predecessors :: g -> Vertex -> [Vertex]
  inEdges :: g -> Vertex -> [Edge]

-- | The interface for immutable graphs with labeled edges.
class HasEdgeLabel g where
  type EdgeLabel g
  edgeLabel :: g -> Edge -> Maybe (EdgeLabel g)

-- | The interface for immutable graphs with labeled vertices.
class HasVertexLabel g where
  type VertexLabel g
  vertexLabel :: g -> Vertex -> Maybe (VertexLabel g)

