require 'set'

class LLNode < Struct.new(:val, :next)
  def self.build(*values)
    return nil if values.empty?

    head = self.new(values[0])

    values[1..].inject(head) do |last_node, val|
      new_node = self.new(val)
      last_node.next = new_node
      new_node
    end

    head
  end

  def to_s
    "(#{val})"
  end

  def inspect
    current = self
    buffer = ""

    found_nodes = Set.new

    while current
      if found_nodes.include?(current.object_id)
        buffer << "{CYCLE:#{current.val}}"

        break
      else
        buffer << "{#{current.val}}"
        buffer << "-" if current.next

        found_nodes << current.object_id
      end

      current = current.next
    end

    buffer
  end

  # For assertions; tests the whole list.
  #
  def ==(other)
    current = self

    while current || other
      if current && other
        return false if current.val != other.val
      else
        return false
      end

      current = current.next
      other = other.next
    end

    true
  end

  # For single node testing/hashing.
  #
  def eql?(other)
    other && val == other.val
  end

  def hash
    val.hash
  end
end
