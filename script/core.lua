Native = {
  __newindex = function (_, n)
    error("attempt to write to undeclared variable "..n, 2)
  end,
  __index = function (_, n)
    error("attempt to read undeclared variable "..n, 2)
  end
}

setmetatable(_G, Native)
