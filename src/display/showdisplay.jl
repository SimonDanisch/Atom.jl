using REPL, Base64

struct JunoDisplay <: AbstractDisplay end

struct JunoEditorInput
  x::Any
end

plotpane_io_ctx(io::IO) = IOContext(io, :juno_plotsize => plotsize(), :juno_colors => syntaxcolors())

const plain_mimes = [
  "image/png",
  "image/jpeg",
  "image/tiff",
  "image/bmp",
  "image/gif"
]

function displayinplotpane(x)
  PlotPaneEnabled[] || return false

  io = IOBuffer()

  # Juno-specific display always takes precedence
  if showable("application/juno+plotpane", x)
    show(plotpane_io_ctx(io), "application/juno+plotpane", x)
    str = String(take!(io))
    startswith(str, "data:") || (str = string("data:text/html,", str))
    @msg ploturl(str)
    return true
  end
  # xml should be in a webview as well because of the possibility of embedded JS
  if showable("image/svg+xml", x)
    # render(PlotPane(), HTML(string("data:image/svg+xml,", stringmime("image/svg+xml", x, context=plotpane_io_ctx(io)))))
    @msg ploturl(string("data:image/svg+xml,", stringmime("image/svg+xml", x, context=plotpane_io_ctx(io))))
    return true
  end

  # images
  for mime in plain_mimes
    if showable(mime, x)
      suffix = istextmime(mime) ? "," : ";base64,"
      str = string("<img src=\"data:", mime, suffix, stringmime(mime, x, context=plotpane_io_ctx(io)), "\">")
      render(PlotPane(), HTML(str))
      return true
    end
  end
  return false
end

using TreeViews: hastreeview, numberofnodes, treelabel, treenode, nodelabel

function Base.display(d::JunoDisplay, x)
  d = last(filter(x -> (x isa REPL.REPLDisplay), Base.Multimedia.displays))
  if displayinplotpane(x)
    # we shouldn't need to do this, but Plots.jl has a ugly overload on display(::REPLDisplay, ::MIME"text/plain" ::Plot)
    # which would otherwise be used
    invoke(display, Tuple{typeof(d), typeof(MIME"text/plain"()), Any}, d, MIME"text/plain"(), x)
    # throw(MethodError(display, "nope"))
  else
    throw(MethodError(display, "nope"))
  end
end

function customdisplaystack()
  old = copy(Base.Multimedia.displays)
  for d in reverse(Base.Multimedia.displays)
    if d isa REPL.REPLDisplay ||
       d isa TextDisplay ||
       d isa JunoDisplay #||
       # d isa Media.DisplayHook
      popdisplay(d)
    end
  end
  old
end

function restoredisplaystack(old)
  empty!(Base.Multimedia.displays)
  foreach(pushdisplay, old)
end

function displayandrender(res)
  if !displayinplotpane(res)
    old = customdisplaystack()
    try
      display(res)
    catch e
    end
    restoredisplaystack(old)
  end

  if hastreeview(res)
    res = generateTreeView(res)
  end

  Juno.render(Juno.Editor(), res)
end

# input from in-editor eval
function Base.display(d::JunoDisplay, wrapper::JunoEditorInput)
  x = wrapper.x
  displayinplotpane(x)

  # TreeViews.jl compat
  if hastreeview(x)
    x = generateTreeView(x)
  end

  Juno.render(Juno.Editor(), x)
end

function best_treelabel(x)
  return applicable(treelabel, IOBuffer(), x, MIME"application/juno+inline"()) ?
          HTML(sprint(treelabel, x, MIME"application/juno+inline"())) :
          applicable(treelabel, IOBuffer(), x, MIME"text/html"()) ?
            HTML(sprint(treelabel, x, MIME"text/html"())) :
            Text(sprint(treelabel, x, MIME"text/plain"()))
end

function best_nodelabel(x, i)
  return applicable(nodelabel, IOBuffer(), x, i, MIME"application/juno+inline"()) ?
          HTML(sprint(nodelabel, x, i, MIME"application/juno+inline"())) :
          applicable(nodelabel, IOBuffer(), x, i, MIME"text/html"()) ?
            HTML(sprint(nodelabel, x, i, MIME"text/html"())) :
            Text(sprint(nodelabel, x, i, MIME"text/plain"()))
end

# TreeViews.jl -> Juno.LazyTree
function generateTreeView(x)
  header = best_treelabel(x)

  numberofnodes(x) == 0 &&  return Tree(header, [])

  genchildren = function ()
    children = Any[]
    for i in 1:numberofnodes(x)
      node = treenode(x, i)
      cheader = best_nodelabel(x, i)

      if isempty(cheader.content)
        node === missing && continue
        push!(children, hastreeview(node) ? generateTreeView(node) : node)
      elseif node === missing
        push!(children, cheader)
      else
        push!(children, SubTree(Row(cheader, text" → "), hastreeview(node) ? generateTreeView(node) : node))
      end
    end
    children
  end

  return LazyTree(header, genchildren)
end
