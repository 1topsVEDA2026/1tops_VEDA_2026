// Stub: cf_math_pkg
// Provides common math functions from PULP common_cells/cf_math_pkg.

package cf_math_pkg;

  // Return the index width for a given number of entries
  function automatic integer unsigned idx_width(input integer unsigned num_entries);
    if (num_entries <= 1)
      return 1;
    else
      return unsigned'($clog2(num_entries));
  endfunction

  // Ceiling division: ceil(a / b)
  function automatic integer unsigned ceil_div(input integer unsigned a, input integer unsigned b);
    if (b == 0) return 0;
    return (a + b - 1) / b;
  endfunction

endpackage : cf_math_pkg
