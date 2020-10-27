module Origen
  MAJOR = 0
  MINOR = 59
  BUGFIX = 3
  DEV = nil
  VERSION = [MAJOR, MINOR, BUGFIX].join(".") + (DEV ? ".pre#{DEV}" : '')
end
