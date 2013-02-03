## This code is written by Davide Albanese, <albanese@fbk.eu>
## (C) 2011 mlpy Developers.

## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.

## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.

## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.


import numpy as np
cimport numpy as np
from libc.stdlib cimport *
from cdtw cimport *

np.import_array()

cdef retrace_path(int n, int m, np.ndarray[np.float_t, ndim=2] cost_arr):
    '''
       Retraces the warping path back from cost_arr.

    :param n: length of the first sequence
    :param m: length of the second sequence
    :param cost_arr: the computed cost array
    :return: (px_arr, py_arr) - warping path for both sequences.
    '''
    cdef Path p
    cdef np.ndarray[np.int_t, ndim=1] px_arr
    cdef np.ndarray[np.int_t, ndim=1] py_arr

    path(<double *> cost_arr.data,
        n, m,
        -1, -1, &p)
    px_arr = np.empty(p.k, dtype=np.int)
    py_arr = np.empty(p.k, dtype=np.int)
    for i in range(p.k):
        px_arr[i] = p.px[i]
        py_arr[i] = p.py[i]
    free (p.px)
    free (p.py)

    return px_arr, py_arr

def dtw_std(x, y, dist_only=True, squared=False, k=None, constraint=None):
    """Standard DTW as described in [Muller07]_,
    using the Euclidean distance (absolute value 
    of the difference) or squared Euclidean distance
    (as in [Keogh01]_) as local cost measure.

    :Parameters:
       x : 1d array_like object (N)
          first sequence
       y : 1d array_like object (M)
          second sequence
       dist_only : bool
          compute only the distance
       squared : bool
          squared Euclidean distance
       constraint: string
          one of the following:
             None or ('None') : unconstrained DTW.
             'sakoe_chiba': DTW constrained by Sakoe & Chiba band of width 2k + 1 (requires value of k set), see [Sakoe78]
             'itakura'    : DTW constrained by Itakura Parallelogram, see
       k : int
          parameter required by sakoe_chiba constraint.
    :Returns:
       dist : float
          unnormalized minimum-distance warp path 
          between sequences
       cost : 2d numpy array (N,M) [if dist_only=False]
          accumulated cost matrix
       path : tuple of two 1d numpy array (path_x, path_y) [if dist_only=False]
          warp path
    
    .. [Muller07] M Muller. Information Retrieval for Music and Motion. Springer, 2007.
    .. [Keogh01] E J Keogh, M J Pazzani. Derivative Dynamic Time Warping. In First SIAM International Conference on Data Mining, 2001.
    .. [Sakoe78] H Sakoe, & S Chiba S. Dynamic programming algorithm optimization for spoken word recognition. Acoustics, 1978
    .. [Itakura75] F Itakura. Minimum prediction residual principle applied to speech recognition. Acoustics, Speech and Signal Processing, IEEE Transactions on, 23(1), 67–72, 1975. doi:10.1109/TASSP.1975.1162641.
    """

    x = np.ascontiguousarray(x, dtype=np.float)
    y = np.ascontiguousarray(y, dtype=np.float)

    if x.ndim == 1 and x.ndim == 1: # Turn one-dimensional array into two-dimensional one
        x = np.reshape(x, (1,-1))
        y = np.reshape(y, (1,-1))

    if x.shape[0] != y.shape[0]:
        raise ValueError('Both sequences must have the same number of dimensions in each element')


    cdef np.ndarray[np.float_t, ndim=2] x_arr
    cdef np.ndarray[np.float_t, ndim=2] y_arr
    cdef np.ndarray[np.float_t, ndim=2] cost_arr

    cdef double dist
    cdef int i
    cdef int sq

    cdef np.ndarray[np.int_t, ndim=1] px_arr
    cdef np.ndarray[np.int_t, ndim=1] py_arr

    # Note the transpose of x and y below, this is because we want user to submit dimensions as rows,
    # but having the sequence as first index is better for looping in C
    x_arr = np.ascontiguousarray(x.T, dtype=np.float)
    y_arr = np.ascontiguousarray(y.T, dtype=np.float)

    cdef int n = x_arr.shape[0]
    cdef int m = y_arr.shape[0]
    cdef int n_dimensions = x_arr.shape[1]

    cost_arr = np.empty((n,m), dtype=np.float)

    if squared: sq = 1
    else: sq = 0

    if constraint is None or constraint == 'None':
        fill_cost_matrix_unconstrained(
            <double *> x_arr.data, <double *> y_arr.data,
            <int> n, <int> m, <int> n_dimensions,
            sq, <double *> cost_arr.data)
    elif constraint == 'sakoe_chiba':
        if k is None:
            raise ValueError('Please specify value of k for Sakoe & Chiba constraint')

        k = int(k)
        if k < 0:
            raise ValueError('Value of k must be greater or equal than 0')

        fill_cost_matrix_with_sakoe_chiba_constraint(
            <double *> x_arr.data, <double *> y_arr.data,
            <int> n, <int> m, <int> n_dimensions,
            sq, <double *> cost_arr.data,
            <int> k
        )
    elif constraint == 'itakura':
        fill_cost_matrix_with_itakura_constraint(
            <double *> x_arr.data, <double *> y_arr.data,
            <int> n, <int> m, <int> n_dimensions,
            sq, <double *> cost_arr.data)

    dist = cost_arr[n-1, m-1]

    if dist_only:
        return dist
    else:
        px_arr, py_arr = retrace_path(x_arr.shape[0], y_arr.shape[0], cost_arr)
        return dist, cost_arr, (px_arr, py_arr)

def dtw_sakoe_chiba(x, y, k, dist_only=True, squared=False):
    """DTW constrained by Sakoe & Chiba band of width 2k+1.
       The warping path is constrained by |i-j| <= k

    :Parameters:
       x : 1d array_like object (N)
          first sequence
       y : 1d array_like object (M)
          second sequence
       dist_only : bool
          compute only the distance
       squared : bool
          squared Euclidean distance
    :Returns:
       dist : float
          unnormalized minimum-distance warp path
          between sequences
       cost : 2d numpy array (N,M) [if dist_only=False]
          accumulated cost matrix
       path : tuple of two 1d numpy array (path_x, path_y) [if dist_only=False]
          warp path

     .. [Sakoe78] H Sakoe, & S Chiba S. Dynamic programming algorithm optimization for spoken word recognition. Acoustics, 1978
     """
    return dtw_std(x, y, dist_only=dist_only, squared=squared, constraint='sakoe_chiba', k=k)

def dtw_itakura(x, y, dist_only=True, squared=False):
    """DTW constrained by Itakura Parallelogram

    :Parameters:
       x : 1d array_like object (N)
          first sequence
       y : 1d array_like object (M)
          second sequence
       dist_only : bool
          compute only the distance
       squared : bool
          squared Euclidean distance
    :Returns:
       dist : float
          unnormalized minimum-distance warp path
          between sequences
       cost : 2d numpy array (N,M) [if dist_only=False]
          accumulated cost matrix
       path : tuple of two 1d numpy array (path_x, path_y) [if dist_only=False]
          warp path

    .. [Itakura75] F Itakura. Minimum prediction residual principle applied to speech recognition. Acoustics, Speech and Signal Processing, IEEE Transactions on, 23(1), 67–72, 1975. doi:10.1109/TASSP.1975.1162641.
    """
    return dtw_std(x, y, dist_only=dist_only, squared=squared, constraint='itakura')

def dtw_subsequence(x, y):
    """Subsequence DTW as described in [Muller07]_,
    assuming that the length of `y` is much larger 
    than the length of `x` and using the Manhattan 
    distance (absolute value of the difference) as 
    local cost measure.

    Returns the subsequence of `y` that are close to `x` 
    with respect to the minimum DTW distance.
    
    :Parameters:
       x : 1d array_like object (N)
          first sequence
       y : 1d array_like object (M)
          second sequence

    :Returns:
       dist : float
          unnormalized minimum-distance warp path
          between x and the subsequence of y
       cost : 2d numpy array (N,M) [if dist_only=False]
          complete accumulated cost matrix
       path : tuple of two 1d numpy array (path_x, path_y)
          warp path

    """

    cdef np.ndarray[np.float_t, ndim=1] x_arr
    cdef np.ndarray[np.float_t, ndim=1] y_arr
    cdef np.ndarray[np.float_t, ndim=2] cost_arr
    cdef np.ndarray[np.int_t, ndim=1] px_arr
    cdef np.ndarray[np.int_t, ndim=1] py_arr
    cdef Path p
    cdef int i
    
    x_arr = np.ascontiguousarray(x, dtype=np.float)
    y_arr = np.ascontiguousarray(y, dtype=np.float)
    cost_arr = np.empty((x_arr.shape[0], y_arr.shape[0]), dtype=np.float)

    subsequence(<double *> x_arr.data, <double *> y_arr.data, 
                 <int> x_arr.shape[0], <int> y_arr.shape[0],
                 <double *> cost_arr.data)
    
    idx = np.argmin(cost_arr[-1, :])
    dist = cost_arr[-1, idx]

    subsequence_path(<double *> cost_arr.data, <int> x_arr.shape[0],
                      <int> y_arr.shape[0], <int> idx, &p)
        
    px_arr = np.empty(p.k, dtype=np.int)
    py_arr = np.empty(p.k, dtype=np.int)
    
    for i in range(p.k):
        px_arr[i] = p.px[i]
        py_arr[i] = p.py[i]
            
    free (p.px)
    free (p.py)

    return dist, cost_arr, (px_arr, py_arr)